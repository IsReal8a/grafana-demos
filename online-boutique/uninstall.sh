#!/bin/bash
set -e

# Uninstaller for Online Boutique Demo with Grafana Alloy
# This script removes all components deployed by the demo

echo "=========================================="
echo "Online Boutique + Grafana Alloy Uninstaller"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="boutique"
ALLOY_NAMESPACE="monitoring"
ALLOY_RELEASE="grafana-cloud"
CONFIRM="no"
CLEANUP_ORPHANS="no"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --alloy-namespace)
      ALLOY_NAMESPACE="$2"
      shift 2
      ;;
    -y|--yes)
      CONFIRM="yes"
      shift
      ;;
    -c|--cleanup-orphans)
      CLEANUP_ORPHANS="yes"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -n, --namespace NAMESPACE        Namespace where Online Boutique is deployed (default: default)"
      echo "  --alloy-namespace NAMESPACE      Namespace where Grafana Alloy is deployed (default: monitoring)"
      echo "  -y, --yes                        Skip confirmation prompts"
      echo "  -c, --cleanup-orphans            Only clean up leftovers from a previous uninstall that got"
      echo "                                   stuck or was force-interrupted (stuck namespace finalizers,"
      echo "                                   dangling webhook configs, cluster-scoped RBAC left behind"
      echo "                                   after the Helm release is gone). Does not touch a healthy,"
      echo "                                   currently-installed release. Skips the normal uninstall flow."
      echo "  -h, --help                       Show this help message"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

echo "Configuration:"
echo "  Online Boutique Namespace: $NAMESPACE"
echo "  Grafana Alloy Namespace: $ALLOY_NAMESPACE"
echo "  Grafana Alloy Release: $ALLOY_RELEASE"
echo ""

# Function to check if resource exists
resource_exists() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  
  if [ -n "$namespace" ]; then
    kubectl get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
  else
    kubectl get "$resource_type" "$resource_name" &>/dev/null
  fi
}

# Waits for a namespace to finish terminating. If it's still stuck after
# $timeout seconds (e.g. the alloy-operator pod died before it could process
# its own uninstall hook), force-clears finalizers on the resources known to
# cause this deadlock (the Alloy CR and the operator Deployment itself) and
# keeps waiting.
wait_for_namespace_deletion() {
  local ns=$1
  local timeout=${2:-30}
  local elapsed=0

  while kubectl get namespace "$ns" &>/dev/null; do
    if [ "$elapsed" -ge "$timeout" ]; then
      echo -e "${YELLOW}Namespace $ns still terminating after ${timeout}s — clearing stuck finalizers${NC}"
      for alloy in $(kubectl get alloys.collectors.grafana.com -n "$ns" -o name 2>/dev/null); do
        kubectl patch "$alloy" -n "$ns" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
      done
      for dep in $(kubectl get deployments -n "$ns" -o name 2>/dev/null); do
        kubectl patch "$dep" -n "$ns" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
      done
      elapsed=0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
}

# Finds and removes leftovers from a previous uninstall that got interrupted
# or was force-cleared (e.g. Colima/the cluster went down mid-uninstall, or a
# stuck namespace finalizer was patched out by hand). These are all
# cluster-scoped resources that a namespace deletion alone never removes:
#   1. A stuck namespace finalizer (Alloy CR / operator Deployment) if the
#      alloy namespace is currently wedged in Terminating.
#   2. Dangling admission webhook configs from the k8s-injection-controller,
#      which point at a webhook Service that no longer exists and will block
#      *any* future install from creating ConfigMaps until removed.
#   3. ClusterRole/ClusterRoleBinding still tagged with this release's Helm
#      ownership annotation, but only when the Helm release itself is gone
#      (if the release still exists, a real install owns these - leave them).
cleanup_orphaned_resources() {
  echo "=========================================="
  echo "Cleaning Up Orphaned Resources"
  echo "=========================================="
  echo ""

  local found=0

  if kubectl get namespace "$ALLOY_NAMESPACE" &>/dev/null; then
    local phase
    phase=$(kubectl get namespace "$ALLOY_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$phase" = "Terminating" ]; then
      found=1
      echo -e "${YELLOW}Namespace $ALLOY_NAMESPACE is stuck Terminating — clearing finalizers${NC}"
      for alloy in $(kubectl get alloys.collectors.grafana.com -n "$ALLOY_NAMESPACE" -o name 2>/dev/null); do
        kubectl patch "$alloy" -n "$ALLOY_NAMESPACE" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null && \
          echo -e "${GREEN}✅ Cleared finalizer on $alloy${NC}"
      done
      for dep in $(kubectl get deployments -n "$ALLOY_NAMESPACE" -o name 2>/dev/null); do
        kubectl patch "$dep" -n "$ALLOY_NAMESPACE" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null && \
          echo -e "${GREEN}✅ Cleared finalizer on $dep${NC}"
      done
      wait_for_namespace_deletion "$ALLOY_NAMESPACE" 10
      echo -e "${GREEN}✅ Namespace $ALLOY_NAMESPACE fully terminated${NC}"
    fi
  fi

  # Only remove a webhook config if the Service it points to is actually gone -
  # matching by name alone would also catch (and destroy) a healthy webhook
  # belonging to a currently-installed, working release.
  for whkind in validatingwebhookconfiguration mutatingwebhookconfiguration; do
    for wh in $(kubectl get "$whkind" -o name 2>/dev/null | grep "$ALLOY_RELEASE" || true); do
      local svc_ns svc_name is_dangling
      svc_ns=$(kubectl get "$wh" -o jsonpath='{.webhooks[0].clientConfig.service.namespace}' 2>/dev/null)
      svc_name=$(kubectl get "$wh" -o jsonpath='{.webhooks[0].clientConfig.service.name}' 2>/dev/null)
      is_dangling="no"
      if [ -n "$svc_name" ] && [ -n "$svc_ns" ]; then
        kubectl get service "$svc_name" -n "$svc_ns" &>/dev/null || is_dangling="yes"
      fi
      if [ "$is_dangling" = "yes" ]; then
        found=1
        echo -e "${YELLOW}Found dangling webhook: $wh (backing service $svc_name.$svc_ns does not exist)${NC}"
        kubectl delete "$wh" --ignore-not-found=true && echo -e "${GREEN}✅ Deleted $wh${NC}"
      fi
    done
  done

  if ! helm status "$ALLOY_RELEASE" -n "$ALLOY_NAMESPACE" &>/dev/null; then
    for kind in clusterrole clusterrolebinding; do
      for name in $(kubectl get "$kind" -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data['items']:
    ann = item['metadata'].get('annotations', {})
    if ann.get('meta.helm.sh/release-name') == '$ALLOY_RELEASE':
        print(item['metadata']['name'])
" 2>/dev/null); do
        found=1
        echo -e "${YELLOW}Found orphaned $kind: $name (release '$ALLOY_RELEASE' is no longer installed)${NC}"
        if [ "$CONFIRM" = "yes" ]; then
          response="y"
        else
          read -p "Delete $kind/$name? (y/n): " -n 1 -r response
          echo ""
        fi
        if [[ $response =~ ^[Yy]$ ]]; then
          kubectl delete "$kind" "$name" --ignore-not-found=true && echo -e "${GREEN}✅ Deleted $kind/$name${NC}"
        else
          echo -e "${YELLOW}⏭️  Skipped $kind/$name${NC}"
        fi
      done
    done
  fi

  echo ""
  if [ "$found" -eq 0 ]; then
    echo -e "${GREEN}✅ No orphaned resources found. Everything looks clean.${NC}"
  else
    echo -e "${GREEN}Cleanup complete.${NC}"
  fi
}

# Function to delete resource with confirmation
delete_resource() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  
  if resource_exists "$resource_type" "$resource_name" "$namespace"; then
    echo -e "${YELLOW}Found $resource_type/$resource_name${NC}"
    if [ "$CONFIRM" = "yes" ]; then
      response="y"
    else
      read -p "Delete $resource_type/$resource_name? (y/n): " -n 1 -r response
      echo ""
    fi
    
    if [[ $response =~ ^[Yy]$ ]]; then
      if [ -n "$namespace" ]; then
        kubectl delete "$resource_type" "$resource_name" -n "$namespace" --ignore-not-found=true
      else
        kubectl delete "$resource_type" "$resource_name" --ignore-not-found=true
      fi
      echo -e "${GREEN}✅ Deleted $resource_type/$resource_name${NC}"
    else
      echo -e "${YELLOW}⏭️  Skipped $resource_type/$resource_name${NC}"
    fi
  fi
}

if [ "$CLEANUP_ORPHANS" = "yes" ]; then
  cleanup_orphaned_resources
  exit 0
fi

# Confirmation prompt
if [ "$CONFIRM" != "yes" ]; then
  echo -e "${RED}WARNING: This will delete the following:${NC}"
  echo "  • Online Boutique application (namespace: $NAMESPACE)"
  echo "  • Grafana Alloy monitoring stack (namespace: $ALLOY_NAMESPACE)"
  echo "  • All associated resources (services, deployments, configmaps, etc.)"
  echo ""
  read -p "Are you sure you want to continue? (yes/no): " -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
  fi
fi

echo "=========================================="
echo "Step 1: Uninstalling Online Boutique"
echo "=========================================="
echo ""

# List of Online Boutique deployments
DEPLOYMENTS=(
  "emailservice"
  "checkoutservice"
  "recommendationservice"
  "frontend"
  "paymentservice"
  "productcatalogservice"
  "cartservice"
  "loadgenerator"
  "currencyservice"
  "shippingservice"
  "redis-cart"
  "adservice"
)

# Delete deployments
for deployment in "${DEPLOYMENTS[@]}"; do
  delete_resource "deployment" "$deployment" "$NAMESPACE"
done

# Delete services
echo ""
echo "Deleting services..."
SERVICES=(
  "emailservice"
  "checkoutservice"
  "recommendationservice"
  "frontend"
  "frontend-external"
  "paymentservice"
  "productcatalogservice"
  "cartservice"
  "currencyservice"
  "shippingservice"
  "redis-cart"
  "adservice"
)

for service in "${SERVICES[@]}"; do
  delete_resource "service" "$service" "$NAMESPACE"
done

# Delete any remaining resources in the namespace
echo ""
echo "Checking for remaining Online Boutique resources..."

# Delete ConfigMaps
if kubectl get configmaps -n "$NAMESPACE" -l app.kubernetes.io/name=online-boutique &>/dev/null; then
  echo -e "${YELLOW}Found Online Boutique ConfigMaps${NC}"
  if [ "$CONFIRM" = "yes" ]; then
    response="y"
  else
    read -p "Delete all Online Boutique ConfigMaps? (y/n): " -n 1 -r response
    echo ""
  fi
  
  if [[ $response =~ ^[Yy]$ ]]; then
    kubectl delete configmaps -n "$NAMESPACE" -l app.kubernetes.io/name=online-boutique --ignore-not-found=true
    echo -e "${GREEN}✅ Deleted ConfigMaps${NC}"
  fi
fi

# Delete ServiceAccounts
if kubectl get serviceaccounts -n "$NAMESPACE" -l app.kubernetes.io/name=online-boutique &>/dev/null; then
  echo -e "${YELLOW}Found Online Boutique ServiceAccounts${NC}"
  if [ "$CONFIRM" = "yes" ]; then
    response="y"
  else
    read -p "Delete all Online Boutique ServiceAccounts? (y/n): " -n 1 -r response
    echo ""
  fi
  
  if [[ $response =~ ^[Yy]$ ]]; then
    kubectl delete serviceaccounts -n "$NAMESPACE" -l app.kubernetes.io/name=online-boutique --ignore-not-found=true
    echo -e "${GREEN}✅ Deleted ServiceAccounts${NC}"
  fi
fi

echo ""
echo "=========================================="
echo "Step 2: Uninstalling Grafana Alloy"
echo "=========================================="
echo ""

# Check if Helm release exists
if helm list -n "$ALLOY_NAMESPACE" | grep -q "$ALLOY_RELEASE"; then
  echo -e "${YELLOW}Found Grafana Alloy Helm release: $ALLOY_RELEASE${NC}"
  if [ "$CONFIRM" = "yes" ]; then
    response="y"
  else
    read -p "Uninstall Grafana Alloy Helm release? (y/n): " -n 1 -r response
    echo ""
  fi
  
  if [[ $response =~ ^[Yy]$ ]]; then
    echo "Uninstalling Helm release..."
    helm uninstall "$ALLOY_RELEASE" -n "$ALLOY_NAMESPACE"
    echo -e "${GREEN}✅ Uninstalled Grafana Alloy Helm release${NC}"
  else
    echo -e "${YELLOW}⏭️  Skipped Grafana Alloy uninstall${NC}"
  fi
else
  echo "Grafana Alloy Helm release not found (may have been already uninstalled)"
fi

# Delete namespace if it exists and is empty
echo ""
if resource_exists "namespace" "$ALLOY_NAMESPACE" ""; then
  echo -e "${YELLOW}Found namespace: $ALLOY_NAMESPACE${NC}"
  if [ "$CONFIRM" = "yes" ]; then
    response="y"
  else
    read -p "Delete namespace $ALLOY_NAMESPACE? (y/n): " -n 1 -r response
    echo ""
  fi
  
  if [[ $response =~ ^[Yy]$ ]]; then
    kubectl delete namespace "$ALLOY_NAMESPACE" --ignore-not-found=true --wait=false
    wait_for_namespace_deletion "$ALLOY_NAMESPACE" 30
    echo -e "${GREEN}✅ Deleted namespace $ALLOY_NAMESPACE${NC}"
  else
    echo -e "${YELLOW}⏭️  Skipped namespace deletion${NC}"
  fi
fi

echo ""
echo "=========================================="
echo "Step 3: Cleanup Temporary Files"
echo "=========================================="
echo ""

# Clean up temporary files created by enable-faro-rum.sh
TEMP_FILES=(
  "/tmp/faro-init.js"
  "/tmp/faro-init.js.bak"
  "/tmp/faro-init-html.html"
  "/tmp/faro-init-html.html.bak"
  "/tmp/faro-package-deps.json"
  "/tmp/faro-snippet.html"
  "/tmp/faro-snippet.html.bak"
  "/tmp/nginx-faro-injection.conf"
  "/tmp/nginx-faro-injection.conf.bak"
  "/tmp/frontend-faro-sidecar-patch.yaml"
)

for file in "${TEMP_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo -e "${YELLOW}Found temporary file: $file${NC}"
    if [ "$CONFIRM" = "yes" ]; then
      response="y"
    else
      read -p "Delete $file? (y/n): " -n 1 -r response
      echo ""
    fi
    
    if [[ $response =~ ^[Yy]$ ]]; then
      rm -f "$file"
      echo -e "${GREEN}✅ Deleted $file${NC}"
    fi
  fi
done

echo ""
echo "=========================================="
echo "Step 4: Verification"
echo "=========================================="
echo ""

echo "Checking for remaining resources..."
echo ""

# Check Online Boutique namespace
echo "Online Boutique namespace ($NAMESPACE):"
REMAINING_PODS=$(kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -E "(frontend|cart|checkout|currency|email|payment|product|recommendation|shipping|ad|redis|loadgenerator)" | wc -l || echo "0")
if [ "$REMAINING_PODS" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Found $REMAINING_PODS remaining pods${NC}"
  kubectl get pods -n "$NAMESPACE" | grep -E "(frontend|cart|checkout|currency|email|payment|product|recommendation|shipping|ad|redis|loadgenerator)"
else
  echo -e "${GREEN}✅ No Online Boutique pods remaining${NC}"
fi

echo ""

# Check Grafana Alloy namespace
if kubectl get namespace "$ALLOY_NAMESPACE" &>/dev/null; then
  echo "Grafana Alloy namespace ($ALLOY_NAMESPACE):"
  REMAINING_ALLOY=$(kubectl get pods -n "$ALLOY_NAMESPACE" 2>/dev/null | tail -n +2 | wc -l || echo "0")
  if [ "$REMAINING_ALLOY" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found $REMAINING_ALLOY remaining pods${NC}"
    kubectl get pods -n "$ALLOY_NAMESPACE"
  else
    echo -e "${GREEN}✅ No Grafana Alloy pods remaining${NC}"
  fi
else
  REMAINING_ALLOY=0
  echo -e "${GREEN}✅ Grafana Alloy namespace deleted${NC}"
fi

echo ""
echo "=========================================="
echo "Uninstall Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  • Online Boutique application removed from namespace: $NAMESPACE"
echo "  • Grafana Alloy monitoring stack removed from namespace: $ALLOY_NAMESPACE"
echo "  • Temporary files cleaned up"
echo ""

if [ "$REMAINING_PODS" -gt 0 ] || [ "$REMAINING_ALLOY" -gt 0 ]; then
  echo -e "${YELLOW}Note: Some resources may still be terminating. Run the following to check:${NC}"
  echo "  kubectl get pods -n $NAMESPACE"
  echo "  kubectl get pods -n $ALLOY_NAMESPACE"
  echo ""
fi
