/**
 * A model of the app's decisions, mirrored from the Swift source: the words
 * of the menu (`UI/Panel/Model/PanelText.swift`) and the poses of the robot
 * (`RobotLook.swift`, `MenuBarLook.swift`). Every function is pure. Times are
 * in seconds.
 */

type WorkState = 'working' | 'waiting' | 'idle';

type Session = {
  /** The state it left, or null when it was first seen in this one. */
  before: WorkState | null;
  /** A command the agent started is still busy. */
  command: boolean;
  /** When it entered the state it counts as now. */
  since: number;
  /** What the agent says about itself. */
  state: WorkState;
};

/** `DetectionSettings.releaseAfterState`. */
export const RELEASE_AFTER = 120;

/** A busy command counts as work, whatever the agent says: a turn that ended is not work that ended (`VerdictRules`). */
function verdict(run: Pick<Session, 'state' | 'command'>): WorkState {
  return run.command ? 'working' : run.state;
}

type Subject = { one: string } | { many: number };

export type Headline = { kind: 'working' | 'finishedRecently' | 'idle'; subject: Subject };

/** `HumaneDuration.counted`. */
function counted(count: number, noun: string): string {
  return count === 1 ? `1 ${noun}` : `${count} ${noun}s`;
}

/**
 * `HumaneDuration.lasting`: "for 12 minutes", "for 1 hour 22 minutes" up to
 * 10 hours, then "for 13 hours", then "for 3 days", or null under a minute.
 */
function lasting(seconds: number): string | null {
  const minutes = Math.floor(Math.max(0, seconds) / 60);
  if (minutes < 1) {
    return null;
  }
  if (minutes < 60) {
    return `for ${counted(minutes, 'minute')}`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 10) {
    const rest = minutes % 60;
    return `for ${rest === 0 ? counted(hours, 'hour') : `${counted(hours, 'hour')} ${counted(rest, 'minute')}`}`;
  }
  return `for ${hours < 48 ? counted(hours, 'hour') : counted(Math.floor(hours / 24), 'day')}`;
}

function phrase(who: Subject, one: string, many: string): string {
  return 'one' in who ? `${who.one} ${one}` : `${who.many} agents ${many}`;
}

/** `PanelText.headline`: the outcome, then the reason. */
export function headlineText(line: Headline): { subtitle: string; title: string } {
  const awake = 'Your Mac stays awake';
  const canSleep = 'Your Mac can sleep';
  switch (line.kind) {
    case 'working':
      return { subtitle: phrase(line.subject, 'is working', 'are working'), title: awake };
    case 'finishedRecently':
      return {
        subtitle: phrase(line.subject, 'finished a moment ago', 'finished a moment ago'),
        title: awake,
      };
    case 'idle':
      return {
        subtitle: 'one' in line.subject ? `${line.subject.one} is idle` : 'All agents are idle',
        title: canSleep,
      };
  }
}

/** `PanelText.working`, `waiting` and `idle`: the phrase of one session. */
export function detailOf(run: Session, now: number): string {
  const time = lasting(now - run.since);
  const startSeen = run.before !== null;
  switch (verdict(run)) {
    case 'working':
      if (run.command) {
        return ['Running 1 command', time].filter(Boolean).join(' ');
      }
      if (time !== null) {
        return `Working ${time}`;
      }
      return startSeen ? 'Started a moment ago' : 'Working';
    case 'waiting':
      if (time !== null) {
        return `Waiting for your answer ${time}`;
      }
      return startSeen ? 'Asked you a moment ago' : 'Waiting for your answer';
    case 'idle':
      if (time !== null) {
        return `Idle ${time}`;
      }
      return run.before === 'working' ? 'Finished a moment ago' : 'Idle';
  }
}

/** `HeroPose`. */
export type Pose = 'awake' | 'reachable' | 'attentive' | 'asleep' | 'paused' | 'off' | 'trouble';

/** `MenuModel.pose(for:)`. */
export function pose(line: Headline): Pose {
  switch (line.kind) {
    case 'working':
    case 'finishedRecently':
      return 'awake';
    case 'idle':
      return 'asleep';
  }
}

/** How much of itself the icon in the menu bar shows while Agent Caffeine keeps nothing awake: off, paused, or all agents done. */
export const ICON_AT_REST = 0.45;

/** `MenuBarLook`: what the robot in the menu bar is drawn from, and the pose it stands for. */
export type IconLook = { eyes: 'happy' | 'open' | 'closed' | 'dead'; opacity: number; pose: Pose };

export function iconLook(of: Pose): IconLook {
  switch (of) {
    case 'awake':
    case 'reachable':
      return { eyes: 'happy', opacity: 1, pose: of };
    case 'attentive':
      return { eyes: 'open', opacity: 1, pose: of };
    // From version 1.0.1 of the app the icon is as pale while the Mac can sleep as while Agent Caffeine is off or paused.
    case 'asleep':
    case 'paused':
    case 'off':
      return { eyes: 'closed', opacity: ICON_AT_REST, pose: of };
    case 'trouble':
      return { eyes: 'dead', opacity: 1, pose: of };
  }
}
