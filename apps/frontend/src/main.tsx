import "./styles.css";

import { ThemeProvider } from "@nonanium/ui";
import { createRouter, RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { routeTree } from "./routeTree.gen";
import { StatusProvider } from "./use-status";

const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider defaultTheme="dark">
      <StatusProvider>
        <RouterProvider router={router} />
      </StatusProvider>
    </ThemeProvider>
  </StrictMode>,
);
