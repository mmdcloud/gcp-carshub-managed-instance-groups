module.exports = {
    apps: [{
      name: "carshub-frontend",
      script: "npm",
      args: "start",
      cwd: "/home/admin_mohitcloud_xyz/nodeapp",
      watch: true,
      env: {
        NODE_ENV: "production",
      }
    }]
  };