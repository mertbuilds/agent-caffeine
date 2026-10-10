import SwiftUI

/// "Wake for jobs" in Settings > Battery and lid: the switch of the
/// feature, and while it is on the jobs that were found with a switch
/// each, "Only on power", where the feature stands, and the history.
///
/// While the helper is not set up or gives no answer, one line says what
/// to do, in place of switches that would do nothing.
struct WakeForJobsSection: View {
    @Binding var settings: JobSettings
    var view = JobWakeView()
    /// For the next runs. A preview passes a time of its own.
    var now = Date()
    var calendar = Calendar.current
    var locale = Locale.current
    /// For a preview.
    var startsWithHistory = false
    /// The user closed the line about a switch that went off by itself.
    var closeSwitchNotice: () -> Void = {}
    @State private var showsHistory: Bool?

    private var historyIsOpen: Bool { showsHistory ?? startsWithHistory }

    /// What keeps the switches from doing anything.
    private var blocker: String? {
        switch view.status {
        case .needsApplications, .needsHelper, .helperSilent:
            return PanelText.jobStatus(view.status, settings: settings, now: now, calendar: calendar, locale: locale)
        case .off, .noAlarm, .asking, .alarmSet, .refused:
            return nil
        }
    }

    var body: some View {
        Section(PanelText.jobsTitle) {
            Toggle(PanelText.jobsSwitch, isOn: $settings.wakeForJobs)
            Text(PanelText.jobsExplained(leadTime: settings.leadTime, holdCap: min(settings.holdCap, JobHold.capLimit)))
                .font(.callout)
                .foregroundStyle(.secondary)
            if settings.wakeForJobs {
                if let blocker {
                    Label(blocker, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    jobs
                    power
                    status
                }
                history
            }
        }
    }

    @ViewBuilder
    private var jobs: some View {
        if view.runs.isEmpty {
            Text(PanelText.jobsNoneFound)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text(PanelText.jobsPerJob)
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(view.runs, id: \.job.id) { run in
                Toggle(isOn: isOn(run)) {
                    Text(run.job.name)
                        .foregroundStyle(hasSwitch(run) ? .primary : .secondary)
                    Text(PanelText.jobDetail(run, now: now, calendar: calendar, locale: locale))
                        .monospacedDigit()
                }
                .disabled(!hasSwitch(run))
            }
        }
        ForEach(ScheduledJob.Source.allCases.filter(isUnreadable), id: \.self) { source in
            Text(PanelText.jobSourceUnreadable(source))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var power: some View {
        Toggle(PanelText.jobsOnPowerOnly, isOn: $settings.onPowerOnly)
        if settings.onPowerOnly {
            Text(PanelText.jobsOnPowerExplained)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Label(PanelText.jobsOnBatteryWarning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var status: some View {
        ForEach(view.lostSwitches, id: \.self) { name in
            HStack(alignment: .firstTextBaseline) {
                Label(PanelText.jobSwitchLost(name), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: closeSwitchNotice) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(PanelText.jobsCloseNotice)
                .accessibilityLabel(PanelText.jobsCloseNotice)
            }
        }
        if let line = PanelText.jobStatus(view.status, settings: settings, now: now, calendar: calendar, locale: locale) {
            Text(line)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var history: some View {
        Button(historyIsOpen ? PanelText.jobsHideHistory : PanelText.jobsShowHistory) { showsHistory = !historyIsOpen }
            .buttonStyle(.link)
        if historyIsOpen {
            if view.history.isEmpty {
                Text(PanelText.jobsNoHistory)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(view.history.enumerated()), id: \.offset) { _, event in
                HStack(alignment: .firstTextBaseline) {
                    Text(PanelText.jobEvent(event, calendar: calendar, locale: locale))
                    Spacer()
                    Text(PanelText.jobEventTime(event.date, now: now, calendar: calendar, locale: locale))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }

    private func isUnreadable(_ source: ScheduledJob.Source) -> Bool {
        if case .unreadable = view.sources[source] { return true }
        return false
    }

    /// False for a job that is listed and cannot be switched on.
    private func hasSwitch(_ run: JobRun) -> Bool {
        !run.tooOften && run.job.noSwitch == nil
    }

    /// A job that runs too often is never on, and so is one that cannot
    /// be told apart from another.
    private func isOn(_ run: JobRun) -> Binding<Bool> {
        Binding(
            get: { hasSwitch(run) && settings.isOn(run.job.id) },
            set: {
                settings.set($0, for: run.job.id)
                closeSwitchNotice()
            }
        )
    }
}
