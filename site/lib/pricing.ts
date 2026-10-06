export type Plan = {
  id: "one" | "three";
  /** How many Macs one key activates. */
  macs: number;
  /** US dollars, paid once. */
  price: number;
  /** The Polar checkout link. A plan without one is not offered. */
  checkoutUrl: string;
};

/** Every price on the site comes from here. */
const ALL_PLANS: readonly Plan[] = [
  {
    id: "one",
    macs: 1,
    price: 19,
    checkoutUrl:
      process.env.NEXT_PUBLIC_BUY_URL ?? "https://buy.polar.sh/polar_cl_UtPTTZP0j4vXcUW47KZQalB2aVkSo3GyKubce3pvdr1",
  },
  {
    id: "three",
    macs: 3,
    price: 29,
    checkoutUrl:
      process.env.NEXT_PUBLIC_BUY_URL_THREE_MACS ??
      "https://buy.polar.sh/polar_cl_8L5mWP6HGDRU1OtZE9aUCiRGYLILln6kWyAKW0qHkIb",
  },
];

/** The plans a reader can buy now, the one for a single Mac first. */
export const PLANS: readonly Plan[] = ALL_PLANS.filter((plan) => plan.checkoutUrl !== "");

/** The plan every button outside the pricing card sells. */
export const BASE_PLAN: Plan = PLANS[0];

export function dollars(plan: Plan): string {
  return `$${plan.price}`;
}

/** "$19", for copy that names one price. */
export const PRICE = dollars(BASE_PLAN);

/** "1 Mac", "3 Macs". */
export function macs(plan: Plan): string {
  return plan.macs === 1 ? "1 Mac" : `${plan.macs} Macs`;
}

/** "$19 for 1 Mac" or "$19 for 1 Mac, $29 for 3 Macs": every plan on offer, for copy that lists them. */
export const PRICE_LIST = PLANS.map((plan) => `${dollars(plan)} for ${macs(plan)}`).join(", ");
