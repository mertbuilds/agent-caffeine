import { Laptop } from "@/components/laptop/laptop";
import { Pill } from "@/components/laptop/pill";
import { Terminal } from "@/components/laptop/terminal";

function Scene({ closed, width, persp, origin, aspect }: { closed: number; width: number; persp: string; origin: string; aspect: string }) {
  return (
    <div
      role="img"
      aria-label="lab lid"
      className="scene relative [container-type:inline-size]"
      style={{ width, aspectRatio: aspect, outline: "1px dashed rgba(255,0,0,0.3)" }}
    >
      <div className="persp absolute inset-0" style={{ perspective: persp, perspectiveOrigin: origin }}>
        <Laptop closed={closed} display={closed > 0.3 ? 0 : 1}>
          <Terminal
            session={{
              welcome: 1,
              typed: 1,
              sent: 1,
              steps: [1, 1, 1, 1, 1, 1],
              working: 120,
              spinner: "✻",
              done: false,
              shown: 1,
            }}
          />
        </Laptop>
        {closed >= 1 && <Pill shown={1} spinner="✻" seconds={312} />}
      </div>
    </div>
  );
}

export default async function Lab({ searchParams }: { searchParams: Promise<Record<string, string>> }) {
  const params = await searchParams;
  const closed = (params.closed ?? "0").split(",").map(Number);
  const rows = Number(params.rows ?? 1);
  const width = Number(params.w ?? 640);
  const persp = params.p ?? "200cqw";
  const origin = params.o ?? "50% 22%";
  const aspect = params.a ?? "10/7";
  return (
    <div id="sheet" style={{ padding: 20, display: "flex", flexDirection: "column", gap: 16, width: "max-content" }}>
      {Array.from({ length: rows }, (_, row) => (
        <div key={row} className="row" style={{ display: "flex", gap: 16, alignItems: "center" }}>
          <div className="label" style={{ width: 120, fontSize: 12, fontFamily: "monospace" }} />
          {closed.map((value) => (
            <Scene key={value} closed={value} width={width} persp={persp} origin={origin} aspect={aspect} />
          ))}
        </div>
      ))}
    </div>
  );
}
