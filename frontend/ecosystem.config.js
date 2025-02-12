module.exports = {
  apps: [{
    name: "carshub-frontend",
    script: "npm",
    args: "start",
    cwd: "/home/milinddixit1967_gmail_com/nodeapp",
    watch: true,
    env: {
      NODE_ENV: "production",
    }
  }]
};