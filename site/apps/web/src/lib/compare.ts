import { m } from '../paraglide/messages.js';
import { agentsMoreThan } from './agents.ts';
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PRICE, dollars } from './pricing.ts';
import { BATTERY_FLOOR } from './simulator.ts';

/** The day every cell about another tool was read on that tool's own page. */
export const CHECKED_ON = '2026-10-08';

export type ToolId = 'ours' | 'adrafinil' | 'holdmylid' | 'lidrun' | 'clamshell' | 'amphetamine';

export type Tool = {
  id: ToolId;
  name: string;
  /** The tool's own pages that its cells were read from. Ours has none: its cells come from this site. */
  sources: ReadonlyArray<{ label: string; url: string }>;
};

/**
 * `unstated` is for what the tool's own pages do not say. It never means no:
 * `no` is only for what the maker says the tool does not do.
 */
export type Value = 'yes' | 'no' | 'partly' | 'unstated';

/** A value with a few words, or `text` alone for a row of words (a price, a date, a list). */
export type Cell = { note?: string; value: Value } | { note?: string; text: string };

export type Row = {
  cells: Record<ToolId, Cell>;
  id: string;
  label: string;
  /** A row where yes is not the better answer: its values are written as words, with no mark. */
  words?: boolean;
};

export const OURS: ToolId = 'ours';

export function tools(): ReadonlyArray<Tool> {
  return [
    { id: 'ours', name: m.app_name(), sources: [] },
    {
      id: 'adrafinil',
      name: 'Adrafinil',
      sources: [
        { label: m.compare_source_readme(), url: 'https://github.com/kageroumado/adrafinil' },
        { label: m.compare_source_site(), url: 'https://kagerou.glass/adrafinil/' },
        {
          label: m.compare_source_releases(),
          url: 'https://github.com/kageroumado/adrafinil/releases',
        },
      ],
    },
    {
      id: 'holdmylid',
      name: 'Hold My Lid',
      sources: [
        { label: m.compare_source_site(), url: 'https://holdmylid.app/' },
        {
          label: m.compare_source_guide(),
          url: 'https://holdmylid.app/blog/keep-mac-awake-ai-coding-agents',
        },
      ],
    },
    {
      id: 'lidrun',
      name: 'LidRun',
      sources: [
        { label: m.compare_source_site(), url: 'https://lidrun.com/' },
        { label: m.compare_source_pricing(), url: 'https://lidrun.com/pricing' },
        { label: m.compare_source_changelog(), url: 'https://lidrun.com/changelog' },
        {
          label: m.compare_source_article(),
          url: 'https://lidrun.com/blog/safe-alternative-to-pmset-disablesleep',
        },
      ],
    },
    {
      id: 'clamshell',
      name: 'Clamshell',
      sources: [
        { label: m.compare_source_site(), url: 'https://clamshell.dev/' },
        {
          label: m.compare_source_guide(),
          url: 'https://clamshell.dev/guides/lidrun-vs-amphetamine-vs-clamshell',
        },
      ],
    },
    {
      id: 'amphetamine',
      name: 'Amphetamine',
      sources: [
        {
          label: m.compare_source_app_store(),
          url: 'https://apps.apple.com/us/app/amphetamine/id937984704',
        },
      ],
    },
  ];
}

function cell(value: Value, note?: string): Cell {
  return note === undefined ? { value } : { note, value };
}
const yes = (note?: string) => cell('yes', note);
const no = (note?: string) => cell('no', note);
const partly = (note: string) => cell('partly', note);
const unstated = () => cell('unstated');
function text(words: string, note?: string): Cell {
  return note === undefined ? { text: words } : { note, text: words };
}

/** The rows in the order a buyer asks: the price first, then the lid, the agents, the stops and the notifications. */
export function rows(): ReadonlyArray<Row> {
  const lidClose = m.compare_note_off_at_lid_close();
  return [
    {
      cells: {
        adrafinil: text(m.compare_price_free(), m.compare_price_adrafinil_note()),
        amphetamine: text(m.compare_price_free(), m.compare_price_amphetamine_note()),
        clamshell: text(m.compare_price_clamshell(), m.compare_note_trial()),
        holdmylid: text(m.compare_price_holdmylid(), m.compare_price_holdmylid_note()),
        lidrun: text(m.compare_price_lidrun(), m.compare_price_lidrun_note()),
        ours: text(
          m.compare_price_ours({ macs: MACS, price: PRICE }),
          LAUNCH_PRICE_ACTIVE
            ? m.compare_price_ours_note_launch({ full: dollars(FULL_PRICE) })
            : m.compare_note_trial(),
        ),
      },
      id: 'price',
      label: m.compare_row_price(),
    },
    {
      cells: {
        adrafinil: partly(m.compare_note_battery_unstated()),
        amphetamine: partly(m.compare_note_battery_unstated()),
        clamshell: yes(),
        holdmylid: yes(m.compare_lid_battery_holdmylid_note()),
        lidrun: yes(m.compare_lid_battery_lidrun_note()),
        ours: yes(),
      },
      id: 'lid-battery',
      label: m.compare_row_lid_battery(),
    },
    {
      cells: {
        adrafinil: yes(m.compare_helper_adrafinil_note()),
        amphetamine: partly(m.compare_helper_amphetamine_note()),
        clamshell: no(),
        holdmylid: unstated(),
        lidrun: yes(m.compare_helper_lidrun_note()),
        ours: yes(m.compare_helper_ours_note()),
      },
      id: 'helper',
      label: m.compare_row_helper(),
      words: true,
    },
    {
      cells: {
        adrafinil: yes(m.compare_works_adrafinil_note()),
        amphetamine: partly(m.compare_works_amphetamine_note()),
        clamshell: no(m.compare_works_clamshell_note()),
        holdmylid: yes(m.compare_works_holdmylid_note()),
        lidrun: partly(m.compare_works_lidrun_note()),
        ours: yes(m.compare_works_ours_note({ count: agentsMoreThan })),
      },
      id: 'works',
      label: m.compare_row_works(),
    },
    {
      cells: {
        adrafinil: yes(m.compare_waits_adrafinil_note()),
        amphetamine: unstated(),
        clamshell: no(),
        holdmylid: unstated(),
        lidrun: partly(m.compare_waits_lidrun_note()),
        ours: yes(),
      },
      id: 'waits',
      label: m.compare_row_waits(),
    },
    {
      cells: {
        adrafinil: yes(),
        amphetamine: partly(m.compare_sleeps_amphetamine_note()),
        clamshell: partly(m.compare_sleeps_clamshell_note()),
        holdmylid: yes(),
        lidrun: yes(),
        ours: yes(),
      },
      id: 'sleeps',
      label: m.compare_row_sleeps(),
    },
    {
      cells: {
        adrafinil: yes(m.compare_battery_stop_adrafinil_note()),
        amphetamine: yes(),
        clamshell: yes(m.compare_battery_stop_clamshell_note()),
        holdmylid: yes(m.compare_note_adjustable()),
        lidrun: yes(m.compare_note_adjustable()),
        ours: yes(m.compare_battery_stop_ours_note({ floor: BATTERY_FLOOR })),
      },
      id: 'battery-stop',
      label: m.compare_row_battery_stop(),
    },
    {
      cells: {
        adrafinil: yes(m.compare_heat_stop_adrafinil_note()),
        amphetamine: unstated(),
        clamshell: yes(m.compare_heat_stop_clamshell_note()),
        holdmylid: unstated(),
        lidrun: yes(),
        ours: yes(),
      },
      id: 'heat-stop',
      label: m.compare_row_heat_stop(),
    },
    {
      cells: {
        adrafinil: partly(m.compare_notifies_adrafinil_note()),
        amphetamine: unstated(),
        clamshell: unstated(),
        holdmylid: partly(m.compare_notifies_holdmylid_note()),
        lidrun: partly(m.compare_notifies_lidrun_note()),
        ours: yes(m.compare_notifies_ours_note()),
      },
      id: 'notifies',
      label: m.compare_row_notifies(),
    },
    {
      cells: {
        adrafinil: unstated(),
        amphetamine: unstated(),
        clamshell: unstated(),
        holdmylid: unstated(),
        lidrun: unstated(),
        ours: yes(),
      },
      id: 'click',
      label: m.compare_row_click(),
    },
    {
      cells: {
        adrafinil: partly(lidClose),
        amphetamine: partly(lidClose),
        clamshell: partly(lidClose),
        holdmylid: partly(lidClose),
        lidrun: unstated(),
        ours: yes(m.compare_dims_ours_note()),
      },
      id: 'dims',
      label: m.compare_row_dims(),
    },
    {
      cells: {
        adrafinil: yes(m.compare_lid_sound_adrafinil_note()),
        amphetamine: unstated(),
        clamshell: unstated(),
        holdmylid: partly(m.compare_lid_sound_holdmylid_note()),
        lidrun: unstated(),
        ours: yes(m.compare_lid_sound_ours_note()),
      },
      id: 'lid-sound',
      label: m.compare_row_lid_sound(),
    },
    {
      cells: {
        adrafinil: yes(),
        amphetamine: partly(m.compare_cli_amphetamine_note()),
        clamshell: partly(m.compare_cli_clamshell_note()),
        holdmylid: unstated(),
        lidrun: yes(m.compare_cli_lidrun_note()),
        ours: yes(),
      },
      id: 'cli',
      label: m.compare_row_cli(),
    },
    {
      cells: {
        adrafinil: yes(),
        amphetamine: unstated(),
        clamshell: unstated(),
        holdmylid: unstated(),
        lidrun: unstated(),
        ours: yes(),
      },
      id: 'mcp',
      label: m.compare_row_mcp(),
    },
    {
      cells: {
        adrafinil: unstated(),
        amphetamine: yes(m.compare_intel_amphetamine_note()),
        clamshell: no(m.compare_intel_clamshell_note()),
        holdmylid: yes(),
        lidrun: yes(),
        ours: yes(),
      },
      id: 'intel',
      label: m.compare_row_intel(),
    },
    {
      cells: {
        adrafinil: text(m.compare_updated_adrafinil()),
        amphetamine: text(m.compare_updated_amphetamine()),
        clamshell: text(m.compare_updated_clamshell()),
        holdmylid: unstated(),
        lidrun: text(m.compare_updated_lidrun()),
        ours: text(m.compare_updated_ours()),
      },
      id: 'updated',
      label: m.compare_row_updated(),
    },
    {
      cells: {
        adrafinil: text(m.compare_also_adrafinil()),
        amphetamine: text(m.compare_also_amphetamine()),
        clamshell: text(m.compare_also_clamshell()),
        holdmylid: text(m.compare_also_holdmylid()),
        lidrun: text(m.compare_also_lidrun()),
        ours: text(m.compare_also_ours()),
      },
      id: 'also',
      label: m.compare_row_also(),
    },
  ];
}

export function isText(cell: Cell): cell is { note?: string; text: string } {
  return 'text' in cell;
}
