import { create, fromBinary, toBinary } from "@bufbuild/protobuf";
import {
  DashboardClientMessageSchema,
  DashboardServerMessageSchema,
  type FleetUpdate,
} from "@/gen/radian/telemetry/v1/telemetry_pb";

export type ConnectionState = "connecting" | "live" | "reconnecting";

export type Viewport = { minLon: number; minLat: number; maxLon: number; maxLat: number };

/**
 * WebSocket client for the broadcast service. Reconnects with backoff and
 * re-sends the latest viewport so the server replies with a fresh snapshot.
 */
export class FleetSocket {
  private ws?: WebSocket;
  private viewport?: Viewport;
  private retry = 0;
  private timer?: ReturnType<typeof setTimeout>;
  private closed = false;

  constructor(
    private url: string,
    private onUpdate: (u: FleetUpdate) => void,
    private onState: (s: ConnectionState) => void,
    private onJobsChanged: (jobIds: string[]) => void = () => {},
  ) {}

  connect() {
    this.closed = false;
    this.onState(this.retry === 0 ? "connecting" : "reconnecting");
    const ws = new WebSocket(this.url);
    ws.binaryType = "arraybuffer";
    this.ws = ws;

    ws.onopen = () => {
      this.retry = 0;
      this.onState("live");
      if (this.viewport) this.sendViewport(this.viewport);
    };
    ws.onmessage = (ev) => {
      const msg = fromBinary(DashboardServerMessageSchema, new Uint8Array(ev.data as ArrayBuffer));
      if (msg.payload.case === "fleetUpdate") this.onUpdate(msg.payload.value);
      else if (msg.payload.case === "jobsChanged") this.onJobsChanged(msg.payload.value.jobIds);
    };
    ws.onclose = () => {
      if (this.closed) return;
      this.onState("reconnecting");
      const delay = Math.min(1000 * 2 ** this.retry++, 15_000) * (0.75 + Math.random() * 0.5);
      this.timer = setTimeout(() => this.connect(), delay);
    };
  }

  setViewport(v: Viewport) {
    this.viewport = v;
    if (this.ws?.readyState === WebSocket.OPEN) this.sendViewport(v);
  }

  private sendViewport(viewport: Viewport) {
    const msg = create(DashboardClientMessageSchema, {
      payload: { case: "subscribe", value: { viewport } },
    });
    this.ws?.send(toBinary(DashboardClientMessageSchema, msg));
  }

  close() {
    this.closed = true;
    clearTimeout(this.timer);
    this.ws?.close();
  }
}
