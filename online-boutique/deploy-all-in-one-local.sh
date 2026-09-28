#!/bin/bash

# All-in-One Deployment for Local Kubernetes (Colima)
# Optimized for: 6 CPU, 8GB RAM (You can add more)
# Deploys: Grafana Alloy + Online Boutique + Load Generator + Span Metrics

set -e

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BOLD}🚀 Online Boutique + Grafana Alloy - All-in-One Deployment${NC}"
echo "================================================================"
echo ""
echo "Target: Local Kubernetes (Colima)"
echo "Resources: 6 CPU, 8GB RAM"
echo ""

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check prerequisites
print_step "Step 1: Checking Prerequisites"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    print_error "Missing $SCRIPT_DIR/.env with GCLOUD_FM_USERNAME and GCLOUD_FM_PASSWORD"
    exit 1
fi
print_success ".env found"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi
print_success "kubectl found"

if ! command -v helm &> /dev/null; then
    print_error "helm is not installed"
    exit 1
fi
print_success "helm found"

if ! command -v colima &> /dev/null; then
    print_error "colima is not installed"
    exit 1
fi
print_success "colima found"

# Detect running Colima profile
print_info "Detecting running Colima profile..."
RUNNING_PROFILE=$(colima list --json 2>/dev/null | grep -o '"name":"[^"]*","status":"Running"' | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -n1)

if [ -z "$RUNNING_PROFILE" ]; then
    print_error "No Colima profile is running"
    echo ""
    echo "Available options:"
    echo "  1. Start default profile: colima start --cpu 6 --memory 8 --kubernetes"
    echo "  2. Start existing profile: colima start grafana-demo-1 --kubernetes"
    echo ""
    exit 1
fi

print_success "Found running Colima profile: $RUNNING_PROFILE"

# Detect the corresponding kubectl context
COLIMA_CONTEXT=$(kubectl config get-contexts -o name | grep "^colima" | grep -i "$RUNNING_PROFILE" | head -n1)
if [ -z "$COLIMA_CONTEXT" ]; then
    # Fallback to any colima context
    COLIMA_CONTEXT=$(kubectl config get-contexts -o name | grep "^colima" | head -n1)
fi

if [ -z "$COLIMA_CONTEXT" ]; then
    print_error "No Colima kubectl context found"
    exit 1
fi

print_info "Using kubectl context: $COLIMA_CONTEXT"

# Switch to the correct context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ "$CURRENT_CONTEXT" != "$COLIMA_CONTEXT" ]; then
    print_info "Switching to context: $COLIMA_CONTEXT"
    kubectl config use-context "$COLIMA_CONTEXT" >/dev/null
fi

if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    echo ""
    echo "Try restarting Colima:"
    echo "  colima stop $RUNNING_PROFILE"
    echo "  colima start $RUNNING_PROFILE --kubernetes"
    exit 1
fi
print_success "Connected to Kubernetes cluster"

# Check cluster resources
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODES" -eq 0 ]; then
    print_error "No nodes found in cluster"
    exit 1
fi
print_success "Cluster has $NODES node(s)"

# Add Grafana Helm repo
print_step "Step 2: Adding Grafana Helm Repository"
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
print_success "Helm repository updated"

# Deploy Grafana Alloy
print_step "Step 3: Deploying Grafana Alloy (Lightweight)"

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

print_info "Installing Grafana k8s-monitoring..."
print_info "This will take 2-3 minutes..."

helm upgrade --install grafana-cloud \
  --namespace monitoring --create-namespace \
  grafana/k8s-monitoring \
  --set "cluster.name=colima-local" \
  --set "collectorCommon.alloy.remoteConfig.enabled=true" \
  --set-string "collectorCommon.alloy.remoteConfig.url=${GCLOUD_FM_URL}" \
  --set-string "collectorCommon.alloy.remoteConfig.auth.username=${GCLOUD_FM_USERNAME}" \
  --set-string "collectorCommon.alloy.remoteConfig.auth.password=${GCLOUD_FM_PASSWORD}" \
  --values - <<EOF
destinations:
  grafana-cloud-otlp:
    type: otlp
    protocol: http
    url: https://otlp-gateway-prod-eu-west-0.grafana.net/otlp
    metrics:
      enabled: true
    logs:
      enabled: true
    traces:
      enabled: true
    auth:
      type: basic
      username: "${GCLOUD_FM_USERNAME}"
      password: "${GCLOUD_FM_PASSWORD}"

  grafana-cloud-profiles:
    type: pyroscope
    url: https://profiles-prod-010.grafana.net
    auth:
      type: basic
      username: "${GCLOUD_FM_USERNAME}"
      password: "${GCLOUD_FM_PASSWORD}"

collectorCommon:
  alloy:
    remoteConfig:
      extraAttributes:
        environment: "development"

collectors:
  alloy:
    presets: [large, root, host-network, host-storage, host-cgroup, clustered, service-discovery, filesystem-log-reader, daemonset, otel-receiver]
    extraService:
      enabled: true
      name: otel-receiver

# Add these if Kubernetes monitoring is enabled
telemetryServices:
  node-exporter:
    deploy: true

  kube-state-metrics:
    deploy: true

  beyla:
    deploy: true
    k8sCache:
      replicas: 1

  opencost:
    deploy: false

  sdkInjector:
    deploy: true
    allowedConfigMapWriters: system:serviceaccount:monitoring:grafana-cloud-alloy
  
profiling:
  enabled: true
  ebpf:
    enabled: true   # node-wide eBPF profiling, fits a daemonset — no app instrumentation needed
    targetingScheme: all   # default is "annotation" (opt-in per pod) - "all" profiles every pod on
                            # the node so the boutique services get profiled without annotating each one

applicationObservability:
  enabled: true
  receivers:
    otlp:
      grpc:
        enabled: true
        port: 4317
      http:
        enabled: true
        port: 4318
    zipkin:
      enabled: true
      port: 9411
  connectors:
    spanMetrics:
      enabled: true
      # Reduce histogram buckets to save ~4000+ series (Grafana support recommendation)
      # Note: Using "2500ms" instead of "2.5s" to avoid Go duration parser issues
      # Key must be histogram.explicit.buckets - a flat "histogramBuckets" key is silently ignored by the chart
      histogram:
        explicit:
          buckets: ["50ms", "100ms", "250ms", "500ms", "1s", "2500ms", "5s", "10s"]
      # service.name is already added by default by the spanmetrics connector (along with
      # span.name, span.kind, status.code) - listing it again fails config validation with
      # "failed validating dimensions: duplicate dimension name \"service.name\""
      dimensions:
        - name: 'k8s.namespace.name'
        - name: 'http.method'
        - name: 'http.status_code'

# Minimal cluster metrics (clustering disabled for single-replica local)
clusterMetrics:
  enabled: true
  clustering:
    enabled: false  # Disable clustering for single-replica local setup
  # V3 SYNTAX: Inject rules into existing pipeline (not orphaned component)
  # Drops Alloy internal histogram buckets to save ~780 series
  extraMetricProcessingRules: |
    rule {
      source_labels = ["__name__"]
      regex         = "alloy_component_(evaluation|dependencies_wait)_seconds_bucket"
      action        = "drop"
    }

EOF

print_success "Grafana Alloy deployed!"

# Wait for Alloy pods
print_info "Waiting for Alloy pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alloy -n ${NAMESPACE} --timeout=180s || true

# Deploy Online Boutique
print_step "Step 4: Deploying Online Boutique Application"

kubectl create namespace ${BOUTIQUE_NS} --dry-run=client -o yaml | kubectl apply -f -

print_info "Deploying application with OpenTelemetry tracing..."

# Get the project root (this script lives at the project root now)
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Create temporary kustomization
TEMP_DIR="$PROJECT_ROOT/.kustomize-temp-local"
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Faro RUM needs a Grafana Cloud Frontend Observability collector URL, which
# is specific to whoever's Grafana Cloud account this is - render it in from
# .env rather than deploying with someone else's hardcoded app ID. If it's
# not set, skip the sidecar entirely rather than deploying a broken one.
FARO_RESOURCE_LINE=""
FARO_COMPONENT_LINE=""
if [ -n "${FARO_COLLECTOR_URL:-}" ]; then
    sed "s|__FARO_COLLECTOR_URL__|${FARO_COLLECTOR_URL}|g; s|__FARO_APP_NAME__|${FARO_APP_NAME:-Online Boutique}|g" \
        "$PROJECT_ROOT/manifests/components/faro/configmap.yaml" > "$TEMP_DIR/faro-configmap.yaml"
    FARO_RESOURCE_LINE="  - ./faro-configmap.yaml"
    FARO_COMPONENT_LINE="  - ../manifests/components/faro"
else
    print_warning "FARO_COLLECTOR_URL not set in .env - skipping Faro RUM sidecar (frontend will deploy without it)"
fi

cat > "$TEMP_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${BOUTIQUE_NS}

resources:
  - ../manifests/resources/app/
${FARO_RESOURCE_LINE}

components:
  - ../manifests/components/tracing
${FARO_COMPONENT_LINE}

# Reduce resource requests for local deployment
patches:
  - patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 50m
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: 64Mi
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: 200m
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 256Mi
    target:
      kind: Deployment

  # adservice is a JVM app; 200m CPU / 256Mi memory is too tight for its
  # startup and heap, causing CrashLoopBackOff and OOMKilled respectively.
  - patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 100m
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: 128Mi
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: 400m
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 450Mi
    target:
      kind: Deployment
      name: adservice
EOF

cd "$TEMP_DIR"
kubectl apply -k .

print_success "Online Boutique deployed!"

# Wait for application pods
print_info "Waiting for application pods to be ready (this may take 3-5 minutes)..."
sleep 15
kubectl wait --for=condition=ready pod -l app=frontend -n ${BOUTIQUE_NS} --timeout=300s || true

# Ask about load generator
print_step "Step 5: Load Generator (Optional)"

echo ""
print_info "The load generator creates continuous traffic to the application."
print_info "This is useful for:"
echo "  • Generating traces and metrics for monitoring"
echo "  • Testing the application under load"
echo "  • Demonstrating observability features"
echo ""
print_warning "It uses ~100MB RAM and generates 5 concurrent users"
echo ""

read -p "Do you want to deploy the load generator? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deploying load generator..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgenerator
  namespace: ${BOUTIQUE_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loadgenerator
  template:
    metadata:
      labels:
        app: loadgenerator
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      terminationGracePeriodSeconds: 5
      restartPolicy: Always
      containers:
      - name: main
        image: gcr.io/google-samples/microservices-demo/loadgenerator:v0.8.0
        env:
        - name: FRONTEND_ADDR
          value: "frontend:80"
        - name: USERS
          value: "5"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF

    print_success "Load generator deployed!"
else
    print_info "Skipping load generator deployment"
    print_info "You can deploy it later with:"
    echo "  kubectl apply -f manifests/resources/loadgenerator/loadgenerator-otel.yaml"
fi

# Show status
print_step "Step 6: Deployment Status"

echo ""
print_info "Grafana Stack Pods:"
kubectl get pods -n ${NAMESPACE}

echo ""
print_info "Online Boutique Pods:"
kubectl get pods -n ${BOUTIQUE_NS}

echo ""
print_info "Services:"
kubectl get svc -n ${BOUTIQUE_NS}

# Final instructions
print_step "✅ Deployment Complete!"

echo ""
echo -e "${BOLD}📊 What was deployed:${NC}"
echo "  • Grafana Alloy with span metrics"
echo "  • Online Boutique (11 microservices)"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  • Load generator (5 concurrent users)"
    echo "  • Total pods: ~17"
    echo "  • Estimated memory usage: ~3-4GB"
else
    echo "  • Load generator: Not deployed"
    echo "  • Total pods: ~16"
    echo "  • Estimated memory usage: ~3GB"
fi
echo ""

echo ""
DASHBOARD_FILE="${SCRIPT_DIR}/dashboards/${GRAFANA_EXECUTIVE_DASHBOARD}.json"
if [ -f "$DASHBOARD_FILE" ]; then
    print_info "Pushing Online Boutique Executive Dashboard to ${GRAFANA_STACK}.grafana.net..."
    DASHBOARD_RESPONSE=$(curl -s -w '\n%{http_code}' -X POST "https://${GRAFANA_STACK}.grafana.net/api/dashboards/db" \
        -H "Authorization: Bearer ${GRAFANA_SA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @"$DASHBOARD_FILE")
    DASHBOARD_HTTP_CODE=$(echo "$DASHBOARD_RESPONSE" | tail -n1)
    DASHBOARD_BODY=$(echo "$DASHBOARD_RESPONSE" | sed '$d')

    if [ "$DASHBOARD_HTTP_CODE" = "200" ]; then
        DASHBOARD_URL=$(echo "$DASHBOARD_BODY" | grep -o '"url":"[^"]*"' | sed 's/"url":"//;s/"$//')
        print_success "Dashboard pushed successfully!"
    else
        print_error "Failed to push dashboard (HTTP $DASHBOARD_HTTP_CODE)"
        echo "$DASHBOARD_BODY"
    fi
else
    print_warning "Dashboard file not found: $DASHBOARD_FILE - skipping dashboard push"
fi
echo ""

echo -e "${BOLD}🌐 Access the Application:${NC}"
echo "  kubectl port-forward -n ${BOUTIQUE_NS} svc/frontend 8080:80"
echo "  Then open: http://localhost:8080"
echo ""

echo -e "${BOLD}📈 Monitor in Grafana Cloud:${NC}"
echo "  • Cluster name: colima-local"
echo "  • Namespace: ${BOUTIQUE_NS}"
echo "  • Span metrics will appear in 2-3 minutes"
echo ""


echo -e "${BOLD}📊 Example Queries:${NC}"
echo ""
echo "Prometheus (Span Metrics):"
echo "  sum by (service_name) (rate(traces_span_metrics_calls_total[5m]))"
echo ""
echo "Loki (Logs):"
echo "  {namespace=\"${BOUTIQUE_NS}\"} |= \"error\""
echo ""
echo "Tempo (Traces):"
echo "  service.name=\"frontend\""
echo ""

echo -e "${BOLD}🔧 Useful Commands:${NC}"
echo "  # Watch pods"
echo "  kubectl get pods -n ${BOUTIQUE_NS} -w"
echo ""
echo "  # View logs"
echo "  kubectl logs -n ${BOUTIQUE_NS} -l app=frontend --tail=50"
echo ""
echo "  # Check Alloy receiver"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=alloy-receiver --tail=50"
echo ""
echo "  # Restart all services"
echo "  kubectl rollout restart deployment -n ${BOUTIQUE_NS}"
echo ""

echo -e "${BOLD}🗑️  Cleanup:${NC}"
echo "  kubectl delete namespace ${BOUTIQUE_NS} ${NAMESPACE}"
echo "  helm uninstall grafana-k8s-monitoring -n ${NAMESPACE}"
echo ""
if [ -n "$DASHBOARD_URL" ]; then
    print_info "View it at: https://${GRAFANA_STACK}.grafana.net${DASHBOARD_URL}"
fi

print_success "All done! Made with love by Isra and happy monitoring! 🎉"
