import type { Metadata } from "next";
import Link from "next/link";
import { PILL, SIZES } from "@/components/pill";
import { Footer } from "@/components/footer";

export const metadata: Metadata = { title: "Page not found · Agent Caffeine" };

export default function NotFound() {
  return (
    <main id="main" className="relative isolate flex min-h-screen flex-col gap-12 overflow-x-clip px-4 pt-[6.5rem] md:px-6">
      <div className="mx-auto flex w-full max-w-[680px] flex-1 flex-col items-start justify-center gap-6 pb-12">
        <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em] md:text-[2.5rem]">
          This page does not exist
        </h1>
        <Link href="/" className={`${PILL} bg-fg text-bg ${SIZES.small}`}>
          Go to the home page
        </Link>
      </div>
      <Footer />
    </main>
  );
}
