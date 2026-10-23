export type Release = {
  /** The build number, when `latest.json` gives one. */
  build?: string;
  /** The name the browser saves the dmg under. */
  filename: string;
  /** The path of the dmg on this site, under `/mac/`. */
  href: string;
  size: number;
  version: string;
};
