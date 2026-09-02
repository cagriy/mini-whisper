import Foundation
import MWConfig
import MWHistory
import MWHotkeys
import MWProfiles
import MWStreaming
import MWSupport
import MWTranscription
import MWUsage

/// Turns a stopped recording into a delivered dictation: finish the stream, pick the
/// transcript, batch-transcribe and clean as needed, bill, paste and record — checking
/// staleness before every network call and before the paste (F12–F15, F21, F26, F28,
/// F29, F35, design §5.5).
///
/// It owns no timers, audio or hotkey state; the controller decides when to run one.
public struct ProcessingJob: Sendable {
    /// F21: a stream that has not finished within 5 s is unusable.
    public static let finishTimeout = Duration.seconds(5)

    private let deps: Dependencies
    private let log = Log.pipeline

    public init(deps: Dependencies) {
        self.deps = deps
    }

    public func run(
        _ input: ProcessingInput,
        isStale: @Sendable () -> Bool,
        emit: @Sendable (UIEvent) -> Void
    ) async {
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
            await bill(streamedSecondsOf: input, seconds: streamedSeconds)
            deps.sounds.playOff()
            emit(.error("No API key configured"))
            return
        }

        var transcribeTokens = TokenUsage()
        if rawText == nil {
            do {
                let instructions = PromptComposer.transcribeInstructions(
                    base: try deps.prompts.transcribeInstructions(),
                    vocabulary: input.config.vocabulary
                )
                let (text, tokens) = try await deps.transcriber.transcribe(
                    wav: input.recording.wav, instructions: instructions
                )
                rawText = text
                transcribeTokens = tokens
            } catch {
                return fail(error, emit: emit)
            }
        }

        let raw = (rawText ?? "").trimmed
        guard !raw.isEmpty else {
            await bill(streamedSecondsOf: input, seconds: streamedSeconds)
            deps.sounds.playOff()
            emit(.idle)
            return
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
                    base: input.profile.cleanupPrompt, vocabulary: input.config.vocabulary
                )
                let (text, tokens) = try await deps.cleaner.clean(raw, prompt: prompt)
                finalText = text
                cleanupTokens = tokens
            } catch {
                return fail(error, emit: emit)
            }
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
            inputTokens: transcribeTokens.inputTokens + cleanupTokens.inputTokens
                + streamedTokens.inputTokens,
            outputTokens: transcribeTokens.outputTokens + cleanupTokens.outputTokens
                + streamedTokens.outputTokens,
            costUSD: cost
        )
        if let engineName, streamedSeconds > 0 {
            usage.streamedSeconds = [engineName.rawValue: streamedSeconds]
        }
        await add(usage)

        do {
            try await deps.paster.paste(
                finalText,
                into: input.target.pid,
                submit: input.binding == .pasteSubmit ? input.profile.submitKey : nil
            )
        } catch {
            return fail(error, emit: emit)
        }

        // F29: history records delivered dictations only.
        do {
            try await deps.history.append(HistoryEntry(
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
        emit(.result(finalText))
        let totals = await deps.usage.totals()
        let rows = Pricing.formatUsageRows(today: totals.today, monthCost: totals.monthCost)
        emit(.usage(today: rows.today, month: rows.month))
    }

    // MARK: - Terminus paths

    /// F15: a stale job bills the seconds it streamed and nothing else.
    private func discard(
        _ input: ProcessingInput,
        seconds: TimeInterval,
        emit: @Sendable (UIEvent) -> Void
    ) async {
        log.debug("stale dictation discarded")
        await bill(streamedSecondsOf: input, seconds: seconds)
        deps.sounds.playOff()
        emit(.idle)
    }

    private func fail(_ error: any Error, emit: @Sendable (UIEvent) -> Void) {
        let message = AnyError(error).description
        log.info("processing failed: \(message)")
        deps.sounds.playOff()
        emit(.error(message))
    }

    private func bill(streamedSecondsOf input: ProcessingInput, seconds: TimeInterval) async {
        guard let engine = input.engine?.name, seconds > 0 else { return }
        await add(ProviderUsage(
            streamedSeconds: [engine.rawValue: seconds],
            costUSD: Pricing.dictationCost(
                engine: engine,
                seconds: seconds,
                tokensByModel: [:],
                overrides: input.config.pricingOverrides
            )
        ))
    }

    private func add(_ usage: ProviderUsage) async {
        do {
            try await deps.usage.add(usage)
        } catch {
            log.warning("usage not recorded: \(AnyError(error).description)")
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
