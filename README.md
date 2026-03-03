# Gateway API Inference Extension Lab

Gateway API Inference Extension의 스마트 라우팅을 테스트하는 환경입니다.

## 구성

| 컴포넌트 | 이미지 | 모델 |
|---------|--------|------|
| Backend (Qwen) | `llm-d-inference-sim` | Qwen3-0.6B |
| EPP | `epp:v1.3.1` | - |
| Envoy Gateway | `v1.6.3` | - |

## 빠른 시작

```bash
./scripts/01-setup-cluster.sh
./scripts/02-install-envoy-gateway.sh
./scripts/03-install-ai-gateway.sh
./scripts/04-deploy-all.sh --monitoring
```

## 테스트

```bash
./test/test-api.sh
./test/load-test.sh
./test/verify-epp-routing.sh check-all
```

## API 접근

```bash
# Gateway IP 확인
kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}'

# API 호출
curl http://<GATEWAY_IP>/v1/models

curl -X POST http://<GATEWAY_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen3-0.6B", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'
```

## 모니터링

```bash
# Grafana: http://localhost:3000 (admin/admin)
# Prometheus: http://localhost:9090
```

### Prometheus 쿼리

```promql
vllm:gpu_cache_usage_perc        # KV-Cache 사용률
vllm:num_requests_waiting        # 대기 중인 요청
vllm:num_requests_running        # 실행 중인 요청
```

## 시뮬레이터 한계

> [!IMPORTANT]
> `llm-d-inference-sim`은 API 호환성 테스트용입니다. GitHub README에 명시되어 있듯이 **"KV-cache blocks usage will always be zero"** 입니다.

| 항목 | 시뮬레이터 | 실제 vLLM |
|-----|-----------|----------|
| API 응답 | ✓ 호환 | ✓ |
| KV-cache 메트릭 | ✗ 항상 0 | ✓ 동적 변화 |
| 큐 메트릭 | ✗ 항상 0 | ✓ 동적 변화 |
| EPP 스마트 라우팅 | ✗ 작동 안함 | ✓ 작동 |

**EPP의 KV-cache/큐 기반 라우팅을 테스트하려면:**
1. 실제 vLLM + GPU 환경 필요
2. 또는 메트릭을 동적으로 시뮬레이션하는 커스텀 mock 서버 필요 (아래 참조)

## Mock vLLM 서버 (스마트 라우팅 테스트용)

동적 메트릭을 시뮬레이션하는 커스텀 mock 서버로 EPP 스마트 라우팅을 테스트할 수 있습니다.

### 테스트 시나리오

| 시나리오 | 설명 | 테스트 내용 |
|---------|------|------------|
| `latency` | 지연 기반 | TTFT 차이로 EPP가 빠른 Pod 선택 |
| `kvcache` | KV-cache 기반 | KV-cache 사용률 차이로 여유있는 Pod 선택 |
| `queue` | 큐 기반 | 동시 처리량 차이로 덜 바쁜 Pod 선택 |

### 사용법

```bash
# 시나리오 1: 지연 기반 라우팅 테스트
./test/test-mock-scenarios.sh latency

# 시나리오 2: KV-cache 기반 라우팅 테스트
./test/test-mock-scenarios.sh kvcache

# 시나리오 3: 큐 기반 라우팅 테스트
./test/test-mock-scenarios.sh queue

# 이미지만 빌드
./test/test-mock-scenarios.sh build

# 정리
./test/test-mock-scenarios.sh clean
```

### Mock 서버 설정

환경변수로 Pod 동작을 제어합니다:

| 변수 | 기본값 | 설명 |
|-----|-------|------|
| `MOCK_VLLM_TTFT_BASE_MS` | 100 | Time-to-first-token (ms) |
| `MOCK_VLLM_ITL_BASE_MS` | 50 | Inter-token latency (ms) |
| `MOCK_VLLM_KV_CACHE_BASE` | 0.1 | 기본 KV-cache 사용률 |
| `MOCK_VLLM_KV_CACHE_PER_REQUEST` | 0.05 | 요청당 KV-cache 증가 |
| `MOCK_VLLM_MAX_CONCURRENT` | 5 | 동시 처리 가능한 요청 수 |

### 메트릭 확인

```bash
# Pod 메트릭 직접 확인
kubectl exec -n ai-gateway <pod-name> -- curl -s localhost:8000/metrics | grep vllm

# EPP 라우팅 로그 확인
kubectl logs -n ai-gateway -l app.kubernetes.io/name=epp --tail=100
```

## 정리

```bash
./scripts/99-cleanup.sh
```

## 참고 자료

- [Gateway API Inference Extension](https://github.com/kubernetes-sigs/gateway-api-inference-extension)
- [Envoy AI Gateway](https://github.com/envoyproxy/ai-gateway)
