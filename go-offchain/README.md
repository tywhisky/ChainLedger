# Go Web3 链下练习

这是一个只用 Go 标准库搭建的最小 Web3 后端骨架。当前包含：

- JSON-RPC 客户端：调用 `eth_blockNumber`
- HTTP API：`GET /healthz`、`GET /chain/head`
- Swagger UI：`http://127.0.0.1:8080/docs/`
- 超时、RPC/HTTP 错误处理与一个最小单元测试

## 运行

先启动任意兼容 EVM JSON-RPC 的本地节点，然后执行：

```bash
cd go-offchain
RPC_URL=http://127.0.0.1:8545 ADDR=:8080 go run ./cmd/server
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/chain/head
go test ./...
```

服务启动后打开 <http://127.0.0.1:8080/docs/>，即可查看并直接调用 API。页面资源来自 CDN，OpenAPI 描述由服务自身的 `/openapi.yaml` 提供。

环境变量：

| 名称 | 默认值 | 用途 |
| --- | --- | --- |
| `RPC_URL` | `http://127.0.0.1:8545` | EVM JSON-RPC 地址 |
| `ADDR` | `:8080` | HTTP 监听地址 |

后续练习顺序见 [ROADMAP.md](ROADMAP.md)。
