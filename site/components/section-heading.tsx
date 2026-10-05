export function SectionHeading({ lead, title }: { lead?: string; title: string }) {
  return (
    <div className="mx-auto flex max-w-[640px] flex-col gap-4 text-center">
      <h2 className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
        {title}
      </h2>
      {lead === undefined ? null : (
        <p className="text-pretty leading-relaxed text-muted">{lead}</p>
      )}
    </div>
  );
}
