import MWMeetings

/// The bundled test-call scripts (design §5.2). Authoring rules:
/// - numbers, dates and times are spelled in `TranscriptNormalizer`'s canonical words, never digits,
///   so an engine writing digits still matches the reference;
/// - no line starts with `-`, which `say` would read as an option;
/// - a line addresses only the scenario's own two characters, never the user.
public enum ScenarioLibrary {
    public static let all: [TestScenario] = [
        make(
            id: "sprint-planning", revision: 1, title: "Sprint planning",
            a: ("Tom", "Daniel"), b: ("Priya", "Karen"),
            lines: [
                (.a, "Morning both. Let's keep this to fifteen minutes; the release review starts at ten thirty."),
                (.b, "Sure. The payments migration is at eighty percent, but the Stripe webhook tests still fail on staging."),
                (.you, "I looked at those yesterday. The failures come from the retry header, not the payload, so it's a one-line fix."),
                (.a, "Good. Can you pair with Priya on it before Thursday?"),
                (.you, "Yes. I'll block two hours tomorrow afternoon, from two until four."),
                (.b, "Then the remaining risk is the Kubernetes upgrade. It needs a maintenance window of about forty minutes."),
                (.a, "Let's ask ops for Wednesday night. Can you send them the runbook?"),
                (.you, "I'll send it today and copy you both. Version three point two has the rollback steps."),
                (.b, "One more thing: design wants the onboarding screens in sprint fourteen, not fifteen."),
                (.a, "That's fine if we drop the CSV export. Nobody has asked for it since March."),
                (.you, "Agreed. I'll move the export ticket to the backlog and update the board after this call."),
                (.a, "Great. Thanks both, see you at the review."),
            ]
        ),
        make(
            id: "budget-review", revision: 1, title: "Budget review",
            a: ("Helen", "Samantha"), b: ("Arjun", "Rishi"),
            lines: [
                (.a, "Thanks for joining. We need to close the marketing budget for the third quarter by Friday."),
                (.b, "The total request is two hundred forty thousand dollars, which is twelve percent over last year."),
                (.you, "Most of that increase is the trade show in Chicago. The booth alone costs thirty five thousand dollars."),
                (.a, "Can we cut the booth size and keep the travel line as it is?"),
                (.you, "A smaller booth saves about eight thousand dollars, roughly a quarter of that line."),
                (.b, "Then the digital spend is the bigger lever. HubSpot ads are returning only one point five percent on click through."),
                (.a, "Arjun, what would you move out of digital?"),
                (.b, "I'd shift fifteen percent of it into the partner program with Salesforce, about eighteen thousand dollars."),
                (.you, "That works for me. I'll update the forecast sheet and send it to finance by Thursday at noon."),
                (.a, "Good. Please flag anything above ten thousand dollars to the CFO before it's committed."),
                (.you, "Will do. I'll also check whether the agency fee still includes the four percent rebate."),
                (.a, "Perfect. Let's sign it off on Friday."),
            ]
        ),
        make(
            id: "incident-review", revision: 1, title: "Incident review",
            a: ("Fiona", "Moira"), b: ("Marcus", "Daniel"),
            lines: [
                (.a, "Let's walk through Tuesday's outage. The first alert fired at two fourteen in the morning."),
                (.b, "PagerDuty woke me at two twenty. By then the API error rate was above thirty percent."),
                (.you, "I was on call as secondary. I joined the bridge at two thirty five and started on the database side."),
                (.a, "What did the Postgres metrics show at that point?"),
                (.you, "Connection pool exhaustion. The primary hit its limit of five hundred connections, and replication lag climbed to ninety seconds."),
                (.b, "That matches the deploy log. A config change at one fifty went out with the pool size halved."),
                (.a, "So the root cause is the config change, not traffic. When did we roll back?"),
                (.you, "The rollback finished at three oh five, and errors were back under one percent by three twenty."),
                (.b, "That puts customer impact at about fifty minutes. We should add a canary stage for config changes."),
                (.a, "Agreed. Marcus, can you draft the postmortem by Friday?"),
                (.you, "I'll add the timeline and the Grafana dashboards to it this afternoon."),
                (.b, "Thanks. I'll circulate it to the team on Monday."),
            ]
        ),
        make(
            id: "hiring-debrief", revision: 1, title: "Hiring debrief",
            a: ("Claire", "Karen"), b: ("Grace", "Tessa"),
            lines: [
                (.a, "We saw three candidates for the analyst role this week. Let's start with Daniela Moreno."),
                (.b, "I liked her a lot. She explained her last project clearly."),
                (.you, "Same here. Her case study was the strongest of the three, though she ran ten minutes over."),
                (.a, "My only worry is experience. She has two years, and the posting asked for four."),
                (.you, "I think she'd grow into it quickly. She already leads the weekly reporting at her current company."),
                (.b, "What about Kwame Asante? He was calm and very direct, but his answers on the budget question were thin."),
                (.a, "Agreed. And Lena Fischer withdrew on Monday, so it's really between the two of them."),
                (.you, "My vote is Daniela. Kwame would be a safe hire, but she has more range."),
                (.b, "I'm happy with that. Claire, can you check her references before we make an offer?"),
                (.a, "Yes. I'll call both referees tomorrow. If they're positive, we offer ninety two thousand."),
                (.you, "She mentioned a notice period of six weeks, so the earliest start would be the first of June."),
                (.b, "That works. I'll tell Kwame on Friday and thank him properly."),
            ]
        ),
        make(
            id: "product-launch", revision: 1, title: "Product launch",
            a: ("Rachel", "Samantha"), b: ("Oliver", "Daniel"),
            lines: [
                (.a, "We're three weeks out from the launch. Is the Lumen Pro still shipping on October fourteenth?"),
                (.b, "It is. The final firmware build, version four point one, goes to the factory on September thirtieth."),
                (.you, "The press embargo lifts on October ninth at nine in the morning, Pacific time."),
                (.a, "Good. And the Lumen Go? Retail wanted both on shelves the same week."),
                (.you, "The Go slips to November. The charging case failed drop testing, and the new mold arrives on the third."),
                (.b, "Then we announce both but only take preorders for the Pro. Pricing stays at two hundred ninety nine dollars."),
                (.a, "Oliver, can you brief the Best Buy and Amazon teams this week?"),
                (.b, "Tomorrow at eleven. I'll share the updated spec sheet with them."),
                (.you, "I'll send the launch deck to both of you tonight, with the new timeline on slide six."),
                (.a, "Thanks. Let's also book a review for the second week of November, once the Go has a firm date."),
                (.you, "I'll find a slot and include the factory team in Shenzhen."),
                (.b, "Great. If the mold arrives on time, we can ship the Go before Thanksgiving."),
            ]
        ),
        make(
            id: "customer-escalation", revision: 1, title: "Customer escalation",
            a: ("Sanjay", "Rishi"), b: ("Bridget", "Moira"),
            lines: [
                (.a, "Harrington Foods called again this morning. Their order still hasn't arrived, and they're threatening to cancel the contract."),
                (.b, "Which order is it? They placed two last week."),
                (.you, "It's order sixty one thousand four hundred eight, the refrigerated units for their Leeds warehouse."),
                (.a, "The tracking shows it left our Rotterdam depot on the twelfth and has been stuck in customs since."),
                (.you, "Customs flagged a missing certificate. I sent it on Tuesday, but nobody confirmed receipt."),
                (.b, "Then let's escalate with the broker. Sanjay, who's our contact there now?"),
                (.a, "Margaret Okafor. I'll call her straight after this and ask for a release within forty eight hours."),
                (.you, "We should also offer Harrington a credit. Their account manager suggested five percent on the next invoice."),
                (.b, "Five percent is fine. Please raise it against invoice nine thousand three hundred seventy and copy me."),
                (.a, "And the second order, sixty one thousand four hundred twelve? That one shipped by air."),
                (.you, "It was delivered on Friday. I'll send their buyer the signed proof of delivery today."),
                (.b, "Good. Let's review the whole account with Margaret on the twentieth."),
            ]
        ),
        make(
            id: "office-move", revision: 1, title: "Office move",
            a: ("Hannah", "Tessa"), b: ("Megan", "Karen"),
            lines: [
                (.a, "The lease on the new office is signed. We move to one hundred forty two Wharf Street on Saturday, April eighteenth."),
                (.b, "Which floor did we end up with? The plans showed both the third and the fifth."),
                (.you, "The fifth floor, suite five hundred ten. It has the larger kitchen and room for forty desks."),
                (.a, "Good. The movers from Atlas Relocations arrive at seven thirty that morning."),
                (.you, "I'll make sure everyone packs their desks by Thursday the sixteenth. Crates go out on Friday."),
                (.b, "What about the internet? Last time it took a week to get the line connected."),
                (.a, "Megan, could you chase Telstra about the broadband installation?"),
                (.b, "Already done. The technician is booked for April fifteenth, between nine and twelve."),
                (.you, "Then the old office at twenty eight Mill Lane can be handed back on the thirtieth."),
                (.a, "The landlord wants the keys back by five that afternoon, and a final meter reading."),
                (.you, "I'll meet the landlord there and take photos of every room before we hand over."),
                (.b, "Perfect. I'll update our address on the website and with the post office."),
            ]
        ),
        make(
            id: "quarterly-sales", revision: 1, title: "Quarterly sales",
            a: ("James", "Daniel"), b: ("Laura", "Samantha"),
            lines: [
                (.a, "Let's go through the third quarter. Revenue came in at four point two million, up nine percent on last year."),
                (.b, "The West region finished first again, mostly on the Meridian Health renewal."),
                (.you, "The Midlands came second at one point one million. That's their best quarter since twenty twenty two."),
                (.a, "Good. Which region came last?"),
                (.b, "The South, for the fourth time this year. They lost two of their top ten accounts in August."),
                (.you, "Both went to Northwind on price. We've already won one of them back with a three-year deal."),
                (.a, "Laura, what's the pipeline looking like for the fourth quarter?"),
                (.b, "About six point eight million in qualified deals, with a forty percent close rate on average."),
                (.you, "That puts us at roughly two point seven million if the rate holds. I'd still forecast two point five to be safe."),
                (.a, "Agreed. Let's present two point five to the board on the twenty first of October."),
                (.you, "I'll build the slides and add a breakdown by region and by quarter."),
                (.b, "Great. Send them over by the nineteenth so we can review them together."),
            ]
        ),
    ]

    public static func scenario(id: String) -> TestScenario? {
        all.first { $0.id == id }
    }

    /// `.named` with an unknown id falls back to a random pick.
    public static func pick(_ choice: ScenarioChoice, using generator: inout some RandomNumberGenerator) -> TestScenario {
        if case .named(let id) = choice, let scenario = scenario(id: id) { return scenario }
        return all[Int.random(in: all.indices, using: &generator)]
    }

    private static func make(
        id: String, revision: Int, title: String,
        a: (character: String, voice: String), b: (character: String, voice: String),
        lines: [(TestCallRole, String)]
    ) -> TestScenario {
        TestScenario(
            id: id, revision: revision, title: title,
            voices: [
                VoiceRole(role: .a, character: a.character, requested: a.voice),
                VoiceRole(role: .b, character: b.character, requested: b.voice),
            ],
            lines: lines.map { ScenarioLine(role: $0.0, text: $0.1) }
        )
    }
}
