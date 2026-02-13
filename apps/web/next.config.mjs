const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseHost = (() => {
  try {
    return new URL(supabaseUrl).hostname;
  } catch {
    return null;
  }
})();

/** @type {import('next').NextConfig} */
const nextConfig = {
  typedRoutes: true,
  images: {
    remotePatterns: [
      ...(supabaseHost
        ? [
            {
              protocol: "https",
              hostname: supabaseHost
            }
          ]
        : []),
      {
        protocol: "http",
        hostname: "127.0.0.1",
        port: "54321"
      },
      {
        protocol: "http",
        hostname: "localhost",
        port: "54321"
      }
    ]
  },
  webpack(config) {
    if (!config.output) {
      config.output = {};
    }
    config.output.uniqueName = "agenda-profissional-web";
    return config;
  }
};

export default nextConfig;
