/** @type {import('next').NextConfig} */
const nextConfig = {
  typedRoutes: true,
  webpack(config) {
    if (!config.output) {
      config.output = {};
    }
    config.output.uniqueName = "agenda-profissional-web";
    return config;
  }
};

export default nextConfig;

