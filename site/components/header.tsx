import Image from "next/image";
import Link from "next/link";
import { BuyButton } from "@/components/buy-button";
import { DownloadButton } from "@/components/download-button";
import { getLatestRelease } from "@/lib/release";

export async function Header() {
  const release = await getLatestRelease();
  return (
    <header className="mx-auto flex w-full max-w-[1120px] items-center justify-between py-5">
      <Link href="/" className="flex items-center gap-2 font-medium no-underline">
        <Image src="/icon.png" alt="" width={28} height={28} priority />
        <span>agent caffeine</span>
      </Link>
      <div className="flex items-center gap-5">
        <Link
          href="/blog"
          className={`text-sm text-muted no-underline transition-colors duration-quick ease-smooth-out hover:text-fg motion-reduce:transition-none ${release === null ? "" : "hidden sm:inline"}`}
        >
          Blog
        </Link>
        {release === null ? (
          <BuyButton placement="header" size="small">
            Buy · $9
          </BuyButton>
        ) : (
          <>
            <BuyButton placement="header" variant="text">
              Buy · $9
            </BuyButton>
            <DownloadButton release={release} placement="header" size="small">
              Download
            </DownloadButton>
          </>
        )}
      </div>
    </header>
  );
}
