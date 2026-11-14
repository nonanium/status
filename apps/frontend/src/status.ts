export type ServiceStatus =
  "unknown" | "online" | "offline" | "timed_out" | "http_error" | "http3_error";

export type Service = {
  id: string;
  name: string;
  url: string;
  checkHttp3: boolean;
  status: ServiceStatus;
  statusCode: number | null;
  latencyMs: number | null;
  error: string | null;
  checkedAt: string | null;
};

export type Category = {
  id: string;
  name: string;
  logo: string;
  services: Service[];
};

export type Severity = "minor" | "major" | "critical";

export type Incident = {
  id: string;
  title: string;
  message: string;
  severity: Severity;
  createdAt: string;
  resolvedAt: string | null;
};

export type Snapshot = {
  categories: Category[];
  incidents: Incident[];
  generatedAt: string;
};

export type StatusMessage =
  | { type: "snapshot"; data: Snapshot }
  | {
      type: "update";
      generatedAt: string;
      services?: (Partial<Service> & { id: string })[];
      incidents?: Incident[];
      removedIncidents?: string[];
    };

export function applyUpdate(
  current: Snapshot | null,
  message: StatusMessage,
): Snapshot {
  if (message.type === "snapshot") return message.data;
  if (message.type !== "update" || !current) {
    throw new Error("Expected an initial status snapshot");
  }
  const services = new Map(
    message.services?.map((service) => [service.id, service]),
  );
  const incidents = new Map(
    current.incidents.map((incident) => [incident.id, incident]),
  );
  for (const id of message.removedIncidents ?? []) incidents.delete(id);
  for (const incident of message.incidents ?? [])
    incidents.set(incident.id, incident);
  return {
    categories: current.categories.map((category) => ({
      ...category,
      services: category.services.map((service) =>
        services.has(service.id)
          ? { ...service, ...services.get(service.id) }
          : service,
      ),
    })),
    incidents: [...incidents.values()],
    generatedAt: message.generatedAt,
  };
}
