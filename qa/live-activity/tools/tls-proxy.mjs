import https from "node:https";
import http from "node:http";
import net from "node:net";
import { readFileSync } from "node:fs";

const [dir, ...routes] = process.argv.slice(2);
const tls = { key: readFileSync(`${dir}/leaf.key`), cert: readFileSync(`${dir}/leaf.pem`) };

for (const route of routes) {
  const [listen, target] = route.split(":").map(Number);
  const handler = (req, res) => {
    const up = http.request(
      { host: "127.0.0.1", port: target, method: req.method, path: req.url, headers: req.headers },
      (r) => {
        res.writeHead(r.statusCode, r.headers);
        r.pipe(res);
      },
    );
    up.on("error", () => {
      res.writeHead(502);
      res.end();
    });
    req.pipe(up);
  };
  const upgrade = (req, socket, head) => {
    const up = net.connect(target, "127.0.0.1", () => {
      const headers = Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join("\r\n");
      up.write(`${req.method} ${req.url} HTTP/1.1\r\n${headers}\r\n\r\n`);
      if (head.length) up.write(head);
      up.pipe(socket);
      socket.pipe(up);
    });
    up.on("error", () => socket.destroy());
    socket.on("error", () => up.destroy());
  };
  for (const host of ["127.0.0.1", "::1"]) {
    const server = https.createServer(tls, handler);
    server.on("upgrade", upgrade);
    server.listen(listen, host, () => console.log(`https://[${host}]:${listen} -> ${target}`));
  }
}
