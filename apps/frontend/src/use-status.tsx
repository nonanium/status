import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";

import { applyUpdate, type Snapshot, type StatusMessage } from "./status";

const StatusContext = createContext<{
  snapshot: Snapshot | null;
  connected: boolean;
  error: Error | null;
} | null>(null);

export function StatusProvider({ children }: { children: ReactNode }) {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let stopped = false;
    let socket: WebSocket;
    let retry: ReturnType<typeof setTimeout>;
    let attempts = 0;

    function connect() {
      const url = new URL("/api/status", window.location.href);
      url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
      socket = new WebSocket(url);
      let current: Snapshot | null = null;

      socket.onmessage = (event) => {
        if (stopped) return;
        try {
          const message = JSON.parse(event.data) as StatusMessage;
          current = applyUpdate(current, message);
          setSnapshot(current);
          setConnected(true);
          setError(null);
          attempts = 0;
        } catch {
          setError(new Error("Invalid status update. Reconnecting..."));
          socket.close();
        }
      };
      socket.onclose = () => {
        if (stopped) return;
        setConnected(false);
        setError(new Error("Connection lost. Displayed data may be outdated."));
        const delay = Math.min(1000 * 2 ** attempts++, 30000);
        retry = setTimeout(connect, delay * (0.75 + Math.random() * 0.5));
      };
    }

    connect();
    return () => {
      stopped = true;
      clearTimeout(retry);
      socket.close();
    };
  }, []);

  return (
    <StatusContext value={{ snapshot, connected, error }}>
      {children}
    </StatusContext>
  );
}

export function useStatus() {
  const status = useContext(StatusContext);
  if (!status) throw new Error("useStatus requires StatusProvider");
  return status;
}
