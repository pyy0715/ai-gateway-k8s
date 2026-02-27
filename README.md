# Envoy AI Gateway Lab

Kubernetes Gateway API Inference Extension과 Envoy AI Gateway를 로컬 환경에서 실습하기 위한 환경입니다.

## 개요

이 프로젝트는 **kind**로 로컬 쿠버네티스 클러스터를 구축하고, **vLLM**으로 LLM을 서빙하며 **Envoy AI Gateway**를 통해 추론 트래픽 라우팅을 검증합니다.

### 구성 요소

- **kind**: 로컬 Kubernetes 클러스터
- **Envoy Gateway**: Gateway API 컨트롤러
- **Envoy AI Gateway**: AI 특화 게이트웨이 컨트롤러
- **vLLM**: OpenAI 호환 LLM 추론 서버 (StatefulSet)
- **InferencePool + EPP**: LLM 특화 스마트 라우팅 (KV-cache, Queue 기반)

## 모델

| 모델 | 크기 | 라이선스 | HF Token | 파일 |
|------|------|----------|----------|------|
| **Qwen/Qwen3-0.6B** | 0.6B | Apache 2.0 | ❌ 불필요 | `vllm-qwen.yaml` (기본) |
| HuggingFaceTB/SmolLM2-1.7B-Instruct | 1.7B | Apache 2.0 | ❌ 불필요 | `vllm-smol.yaml` |

> **Note**: 두 모델 모두 Apache 2.0 라이선스로 HF Token 없이 사용 가능합니다.
> Qwen3는 기본적으로 thinking mode가 활성화되어 있습니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    kind Cluster                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              envoy-gateway-system                    │   │
│  │  Envoy Proxy (Data Plane) + Gateway Controller      │   │
│  └─────────────────────┬───────────────────────────────┘   │
│                        │                                    │
│  ┌─────────────────────▼───────────────────────────────┐   │
│  │            envoy-ai-gateway-system                   │   │
│  │  AI Gateway Controller                              │   │
│  │  • body에서 model 필드 추출 → x-ai-eg-model 주입    │   │
│  └─────────────────────┬───────────────────────────────┘   │
│                        │                                    │
│  ┌─────────────────────▼───────────────────────────────┐   │
│  │                default namespace                     │   │
│  │                                                      │   │
│  │  Gateway ─► AIGatewayRoute ─► InferencePool         │   │
│  │     │            │                   │              │   │
│  │     │            │                   ▼              │   │
│  │     │            │         ┌─────────────────┐     │   │
│  │     │            │         │  EPP (gRPC)     │     │   │
│  │     │            │         │  • KV-cache     │     │   │
│  │     │            │         │  • Queue depth  │     │   │
│  │     │            │         │  • Prefix cache │     │   │
│  │     │            │         └────────┬────────┘     │   │
│  │     │            │                  │              │   │
│  │     │            ▼                  ▼              │   │
│  │     │    StatefulSet (Qwen3 / SmolLM2)             │   │
│  │     │    • 각 Pod마다 전용 PVC (RWO)               │   │
│  │     │    • 메트릭: :8000/metrics                   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 라우팅 흐름

1. **Client** → Envoy Proxy (Gateway)
2. **Gateway** → body에서 `model` 필드 추출 → `x-ai-eg-model` 헤더 자동 주입
3. **AIGatewayRoute** → `x-ai-eg-model` 헤더 기반 매칭
4. **InferencePool** → EPP(Endpoint Picker)에게 Pod 선택 위임
5. **EPP** → KV Cache, Queue, Prefix Cache 기반으로 최적 Pod 선택

## 사전 요구사항

### 필수 도구
- **Docker**: kind 실행용
- **kubectl**: Kubernetes CLI
- **helm**: 패키지 매니저
- **curl**: API 테스트용

### 하드웨어 요구사항 (CPU-only)

> ⚠️ **중요**: vLLM을 CPU로 실행하면 OS + KV-cache까지 합쳐 **16GB RAM**이 필요합니다.

| 리소스 | 최소 | 권장 |
|--------|------|------|
| CPU | 4코어 | 8코어 |
| RAM | **16GB** | 32GB |
| Disk | 20GB | 50GB |

## 빠른 시작

### 1. 클러스터 생성

```bash
chmod +x scripts/*.sh test/*.sh
./scripts/01-setup-cluster.sh
```

### 2. Gateway API CRD 설치

```bash
./scripts/02-install-gateway-api.sh
```

### 3. Envoy Gateway 설치

```bash
./scripts/03-install-envoy-gateway.sh
```

### 4. AI Gateway 설치

```bash
./scripts/04-install-ai-gateway.sh
```

### 5. 모든 리소스 배포

```bash
# 기본 배포 (Qwen3 only)
./scripts/05-deploy-all.sh

# 모니터링 포함
./scripts/05-deploy-all.sh --monitoring

# 두 모델 모두 배포 + 모니터링
./scripts/05-deploy-all.sh --all
```

> **Note**: vLLM은 첫 실행 시 모델을 다운로드하므로 Pod가 Ready 상태가 될 때까지 몇 분 정도 걸릴 수 있습니다.

### 6. API 테스트

```bash
./test/test-api.sh
```

## 수동 테스트

### 포트 포워딩

```bash
kubectl port-forward -n default service/ai-gateway 8081:80 &
```

### API 호출

#### x-ai-eg-model 헤더 동작 방식

**중요**: Gateway가 요청 body의 `model` 필드에서 자동으로 `x-ai-eg-model` 헤더를 추출하여 주입합니다.

```bash
# 방법 1: body의 model 필드만 사용 (권장)
# Gateway가 자동으로 x-ai-eg-model 헤더 주입
curl -X POST http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'

# 방법 2: x-ai-eg-model 헤더 직접 지정
curl -X POST http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: Qwen/Qwen3-0.6B" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'

# SmolLM2 사용 (--smol 플래그로 배포한 경우)
curl -X POST http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "HuggingFaceTB/SmolLM2-1.7B-Instruct",
    "messages": [{"role": "user", "content": "What is 2+2?"}],
    "max_tokens": 50
  }'

# Models List
curl http://localhost:8081/v1/models
```

## EPP 스마트 라우팅

EPP(Endpoint Picker)는 다음 메트릭을 기반으로 최적의 Pod를 선택합니다:

| 메트릭 | 설명 | vLLM 엔드포인트 |
|--------|------|-----------------|
| `vllm:gpu_cache_usage_perc` | KV-cache 사용률 | `:8000/metrics` |
| `vllm:num_requests_waiting` | 대기 중인 요청 (Queue depth) | `:8000/metrics` |
| `vllm:num_requests_running` | 실행 중인 요청 | `:8000/metrics` |

> **Note**: vLLM 메트릭은 메인 서버 포트(8000)의 `/metrics` 엔드포인트에서 기본 노출됩니다.

## 모니터링

모니터링 스택을 배포한 경우 (`--monitoring` 플래그):

```bash
# Prometheus UI
kubectl port-forward svc/prometheus 9090:9090
# http://localhost:9090

# Grafana UI (admin/admin)
kubectl port-forward svc/grafana 3000:3000
# http://localhost:3000
```

### 유용한 Prometheus 쿼리

```promql
# KV-Cache 사용률
vllm:gpu_cache_usage_perc

# 대기 중인 요청 (Queue Depth)
vllm:num_requests_waiting

# 실행 중인 요청
vllm:num_requests_running

# 요청 지연 시간 (P95)
histogram_quantile(0.95, rate(vllm:e2e_request_latency_seconds_bucket[5m]))
```

### EPP 검증

```bash
./test/verify-epp-routing.sh check-all
```

### 로드 테스트

```bash
# 기본 테스트
./test/load-test.sh

# 부하 테스트
./test/load-test.sh --requests 100 --concurrent 10 --prompt-length long
```

## 상태 확인

```bash
# 모든 Pod 상태
kubectl get pods -A | grep -E "vllm|envoy|ai-gateway"

# vLLM 로그 (모델 다운로드 진행 상황)
kubectl logs -l app=vllm-qwen -f

# StatefulSet 상태
kubectl get statefulset

# Gateway 상태
kubectl get gateway -A

# AIGatewayRoute 상태
kubectl get aigatewayroute -A

# InferencePool 상태
kubectl get inferencepool -A
```

## 정리

```bash
./scripts/99-cleanup.sh
```

## 디렉토리 구조

```
ai-gateway-k8s/
├── README.md
├── kind-config.yaml              # kind 클러스터 설정
├── scripts/
│   ├── 01-setup-cluster.sh       # kind 클러스터 생성
│   ├── 02-install-gateway-api.sh # Gateway API CRD 설치
│   ├── 03-install-envoy-gateway.sh
│   ├── 04-install-ai-gateway.sh
│   ├── 05-deploy-all.sh          # --monitoring, --smol, --all 옵션
│   └── 99-cleanup.sh
├── k8s/
│   ├── backend/
│   │   ├── vllm-qwen.yaml        # StatefulSet (Qwen3, 기본)
│   │   └── vllm-smol.yaml        # StatefulSet (SmolLM2)
│   ├── inference-pool/
│   │   ├── epp-rbac.yaml         # 기본 EPP RBAC
│   │   ├── epp-config.yaml       # 스케줄링 플러그인
│   │   ├── epp-deployment.yaml   # 기본 EPP (Qwen)
│   │   ├── inference-pool.yaml   # 기본 InferencePool (Qwen)
│   │   ├── inference-objective.yaml
│   │   └── pool-smol/            # SmolLM 전용 EPP + Pool
│   │       ├── epp-config.yaml
│   │       ├── epp-deployment.yaml
│   │       ├── epp-rbac.yaml
│   │       └── inference-pool.yaml
│   ├── ai-gateway/
│   │   ├── gateway.yaml          # GatewayClass + Gateway
│   │   └── ai-gateway-route.yaml # AIGatewayRoute
│   └── monitoring/
│       ├── prometheus.yaml       # Prometheus
│       └── grafana.yaml          # Grafana + 대시보드
└── test/
    ├── test-api.sh               # API 테스트
    ├── load-test.sh              # 부하 테스트
    └── verify-epp-routing.sh     # EPP 검증
```

## 참고 자료

- [Envoy AI Gateway](https://github.com/envoyproxy/ai-gateway)
- [Gateway API Inference Extension](https://github.com/kubernetes-sigs/gateway-api-inference-extension)
- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [kind](https://kind.sigs.k8s.io/)
- [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B)
- [SmolLM2-1.7B-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct)
