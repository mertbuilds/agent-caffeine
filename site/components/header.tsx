import Image from "next/image";
import Link from "next/link";
import { BuyButton } from "@/components/buy-button";

export function Header() {
  return (
    <header className="mx-auto flex w-full max-w-[1120px] items-center justify-between py-5">
      <Link href="/" className="flex items-center gap-2 font-medium no-underline">
        <Image src="/icon.png" alt="" width={28} height={28} priority />
        <span>agent caffeine</span>
      </Link>
      <div className="flex items-center gap-5">
        <Link
          href="/blog"
          className="text-sm text-muted no-underline transition-colors duration-quick ease-smooth-out hover:text-fg motion-reduce:transition-none"
        >
          Blog
        </Link>
        <BuyButton placement="header" size="small">
          Buy · $9
        </BuyButton>
      </div>
    </header>
  );
}
