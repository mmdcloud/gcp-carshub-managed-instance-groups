module.exports = {
    apps: [{
      name: "carshub-frontend",
      script: "npm",
      args: "start",
      cwd: "/nodeapp",
      watch: true,
      env: {
        NODE_ENV: "production",
      }
    }]
  };