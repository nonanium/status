import { nonaniumUi } from "@nonanium/ui/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  server: {
    proxy: {
      "/api/status": { target: "http://127.0.0.1:8080", ws: true },
    },
  },
  plugins: [
    tanstackRouter({ target: "react", autoCodeSplitting: true }),
    tailwindcss(),
    react(),
    nonaniumUi({ defaultThemeId: "nonanium" }),
  ],
});
