// Penpot 2.18.1 exporter calls server.listen(port) without a host, despite
// declaring an http-server-host setting. With host networking this opens
// every interface. Apply only to its fixed HTTP port; preserve other sockets.
// Remove when a pinned upstream release passes the host to server.listen.
const net = require("node:net");
const listen = net.Server.prototype.listen;

net.Server.prototype.listen = function (...args) {
  if (args[0] === 6061 || args[0] === "6061") {
    if (typeof args[1] === "function") {
      args.splice(1, 0, "127.0.0.1");
    } else {
      args[1] = "127.0.0.1";
    }
  }
  return Reflect.apply(listen, this, args);
};
