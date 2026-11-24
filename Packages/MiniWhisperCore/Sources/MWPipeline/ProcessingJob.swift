import Foundation
import MWConfig
import MWCorrections
import MWHistory
import MWHotkeys
import MWProfiles
import MWStats
import MWStreaming
import MWSupport
import MWTranscription
import MWUsage

/// Turns a stopped recording into a delivered dictation: finish the stream, pick the
/// transcript, batch-transcribe and clean as needed, bill, paste and record — checking
/// staleness before every network call and before the paste (F12–F15, F21, F26, F28,
/// F29, F35, design §5.5). Every run, whatever ends it, records one attempt.
///
/// It owns no timers, audio or hotkey state; the controller decides when to run one.
public struct ProcessingJob: Sendable {
    private typealias Ending = (outcome: DictationAttempt.Outcome, words: Int, cost: Double, wait: Double?)

    /// F21: a stream that has not finished within 5 s is unusable.
    public static let finishTimeout = Duration.seconds(5)

    private let deps: Dependencies
    private let clock: any Clock
    private let billing: StreamBilling
    private let log = Log.pipeline

    public init(deps: Dependencies, clock: any Clock) {
        self.deps = deps
        self.clock = clock
        billing = StreamBilling(usage: deps.usage)
    }

    public func run(
        _ input: ProcessingInput,
        isStale: @Sendable () -> Bool,
        emit: @Sendable (UIEvent) -> Void
    ) async {
        let id = UUID().uuidString
        let ending = await perform(input, id: id, isStale: isStale, emit: emit)
        await deps.stats.record(DictationAttempt(
            id: id,
            bundleID: input.target.bundleID,
            engine: input.engine?.name.rawValue,
            seconds: input.recording.duration,
            words: ending.words,
            outcome: ending.outcome,
            wait: ending.wait,
            costUSD: ending.cost
        ))
    }

    private func perform(
        _ input: ProcessingInput,
        id: String,
        isStale: @Sendable () -> Bool,
        emit: @Sendable (UIEvent) -> Void
    ) async -> Ending {
        var streamedSeconds = 0.0
        var streamedTokens = TokenUsage()
        var rawText: String?

        if let engine = input.engine {
            let result = await engine.finish(timeout: Self.finishTimeout)
            streamedSeconds = result.usage.seconds
            let text = result.text.trimmed
            if result.ok, !text.isEmpty, input.sink?.failed != true {
                rawText = text
                streamedTokens = TokenUsage(
                    inputTokens: result.usage.inputTokens,
                    outputTokens: result.usage.outputTokens
                )
                log.info("\(engine.name.rawValue): streamed transcript used")
            } else {
                input.sink?.markUnavailable()
                log.info("\(engine.name.rawValue): streamed transcript unusable — batch fallback")
            }
        }

        // Checkpoint 1 of F15: a newer press has already superseded this dictation.
        guard !isStale() else { return await discard(input, seconds: streamedSeconds, emit: emit) }

        let key = (try? deps.secrets.secret(for: .openai)).flatMap { $0.isEmpty ? nil : $0 }
        // F13: without a key the streamed transcript is pasted raw, or nothing is.
        guard key != nil || rawText != nil else {
            let cost = await bill(streamedSecondsOf: input, seconds: streamedSeconds)
            deps.sounds.playOff()
            emit(.error("No API key configured"))
            return (.noKey, 0, cost, nil)
        }

        let snapshot = input.snapshot
        let releaseHints = HintResolver.resolve(snapshot, bundleID: input.target.bundleID)
        let rules = CorrectionResolver(rules: snapshot.rules).rules(for: input.target.bundleID)

        var transcribeTokens = TokenUsage()
        if rawText == nil {
            do {
                let prompt = PromptComposer.transcribePrompt(
                    base: try deps.prompts.transcribeInstructions(),
                    terms: releaseHints.terms
                )
                let (text, tokens) = try await deps.transcriber.transcribe(
                    wav: input.recording.wav, prompt: prompt
                )
                rawText = text
                transcribeTokens = tokens
            } catch {
                return fail(error, cost: 0, emit: emit)
            }
        }

        let raw = (rawText ?? "").trimmed
        guard !raw.isEmpty else {
            let cost = await bill(streamedSecondsOf: input, seconds: streamedSeconds)
            deps.sounds.playOff()
            emit(.idle)
            return (.empty, 0, cost, nil)
        }

        var finalText = raw
        var cleanupTokens = TokenUsage()
        let cleanup = EffectiveCleanup.isOn(
            config: input.config, hasOpenAIKey: key != nil, profile: input.profile
        )
        if cleanup {
            // Checkpoint 2 of F15.
            guard !isStale() else { return await discard(input, seconds: streamedSeconds, emit: emit) }
            do {
                let prompt = PromptComposer.cleanupPrompt(
                    base: input.profile.cleanupPrompt, hints: releaseHints, rules: rules
                )
                let (text, tokens) = try await deps.cleaner.clean(raw, prompt: prompt)
                finalText = text
                cleanupTokens = tokens
            } catch {
                return fail(error, cost: 0, emit: emit)
            }
        }

        // R14: exactly once, on whatever the cleanup left behind, before delivery.
        let corrected = CorrectionApplier(rules: rules).apply(to: finalText)
        finalText = corrected.text
        if corrected.replacements > 0 {
            // R26: counts only — the phrases are the user's own words.
            log.info(
                "corrections: \(corrected.replacements) replacement(s) from \(rules.count) rule(s)"
            )
        }

        // Checkpoint 3 of F15: the last chance to stop before the text reaches another app.
        guard !isStale() else { return await discard(input, seconds: streamedSeconds, emit: emit) }

        var tokensByModel: [String: TokenUsage] = [:]
        if transcribeTokens.inputTokens != 0 || transcribeTokens.outputTokens != 0 {
            tokensByModel[OpenAIClient.transcribeModel] = transcribeTokens
        }
        if cleanup { tokensByModel[OpenAIClient.cleanupModel] = cleanupTokens }

        let engineName = input.engine?.name
        let cost = Pricing.dictationCost(
            engine: engineName,
            seconds: streamedSeconds,
            tokensByModel: tokensByModel,
            overrides: input.config.pricingOverrides
        )
        var usage = ProviderUsage(
            purpose: .dictation,
            inputTokens: transcribeTokens.inputTokens + cleanupTokens.inputTokens
                + streamedTokens.inputTokens,
            outputTokens: transcribeTokens.outputTokens + cleanupTokens.outputTokens
                + streamedTokens.outputTokens,
            costUSD: cost
        )
        if let engineName, streamedSeconds > 0 {
            usage.streamedSeconds = [engineName.rawValue: streamedSeconds]
        }
        await billing.add(usage)

        do {
            try await deps.paster.paste(
                finalText,
                into: input.target.pid,
                submit: input.binding == .pasteSubmit ? input.profile.submitKey : nil
            )
        } catch {
            return fail(error, cost: cost, emit: emit)
        }
        let wait = clock.now - input.releasedAt

        // F29: history records delivered dictations only.
        do {
            try await deps.history.append(HistoryEntry(
                id: id,
                text: finalText,
                appName: input.target.name,
                bundleID: input.target.bundleID,
                engine: engineName?.rawValue,
                streamedSeconds: streamedSeconds,
                costUSD: cost
            ))
        } catch {
            log.warning("history append failed: \(AnyError(error).description)")
        }

        deps.sounds.playOff()
        emit(.result(DeliveredDictation(
            text: finalText,
            appName: input.target.name,
            bundleID: input.target.bundleID,
            engine: engineName,
            deliveredAt: Date()
        )))
        emit(.usage(await deps.usage.totals()))
        return (.delivered, WordCount.count(finalText), cost, wait)
    }

    // MARK: - Terminus paths

    /// F15: a stale job bills the seconds it streamed and nothing else.
    private func discard(
        _ input: ProcessingInput,
        seconds: TimeInterval,
        emit: @Sendable (UIEvent) -> Void
    ) async -> Ending {
        log.debug("stale dictation discarded")
        let cost = await bill(streamedSecondsOf: input, seconds: seconds)
        deps.sounds.playOff()
        emit(.idle)
        return (.superseded, 0, cost, nil)
    }

    /// `cost` is what the dictation was billed before it failed.
    private func fail(_ error: any Error, cost: Double, emit: @Sendable (UIEvent) -> Void) -> Ending {
        let message = AnyError(error).description
        log.info("processing failed: \(message)")
        deps.sounds.playOff()
        emit(.error(message))
        return (.failed, 0, cost, nil)
    }

    private func bill(streamedSecondsOf input: ProcessingInput, seconds: TimeInterval) async -> Double {
        await billing.record(
            engine: input.engine?.name,
            seconds: seconds,
            overrides: input.config.pricingOverrides
        )
    }
}

/// Streamed seconds are billed whether or not the dictation is delivered — a discarded,
/// gated, aborted or stale stream still costs its per-minute rate (F11, F15, F35).
struct StreamBilling: Sendable {
    let usage: any UsageRecording
    private let log = Log.pipeline

    init(usage: any UsageRecording) {
        self.usage = usage
    }

    /// The cost billed: 0 without an engine or seconds.
    @discardableResult
    func record(engine: EngineName?, seconds: TimeInterval, overrides: [String: Double]) async -> Double {
        guard let engine, seconds > 0 else { return 0 }
        let cost = Pricing.dictationCost(engine: engine, seconds: seconds, tokensByModel: [:], overrides: overrides)
        await add(ProviderUsage(purpose: .dictation, streamedSeconds: [engine.rawValue: seconds], costUSD: cost))
        return cost
    }

    func add(_ providerUsage: ProviderUsage) async {
        do {
            try await usage.add(providerUsage)
        } catch {
            log.warning("usage not recorded: \(AnyError(error).description)")
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
