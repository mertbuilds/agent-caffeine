import Image from "next/image";
import { BuyButton } from "@/components/buy-button";

export function Header() {
  return (
    <header className="mx-auto flex w-full max-w-[960px] items-center justify-between py-5">
      <div className="flex items-center gap-2 font-medium">
        <Image src="/icon.png" alt="" width={28} height={28} priority />
        <span>Agent Caffeine</span>
      </div>
      <BuyButton placement="header" size="small">
        Buy · $9
      </BuyButton>
    </header>
  );
}
