/** @type {import('next').NextConfig} */
module.exports = {
  reactStrictMode: true,
  // The portless dev URLs; without them Next refuses the dev client and the page never hydrates.
  allowedDevOrigins: ["caffeinagent.local", "caffeinagent.localhost"],
};
