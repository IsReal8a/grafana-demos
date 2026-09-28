#!/bin/bash

# Demo Error Simulation Script for Online Boutique
# This script provides realistic failure scenarios for demonstrating observability

set -e

NAMESPACE="boutique"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Same spec deploy-all-in-one-local.sh applies inline - kept in sync here so
# this script doesn't depend on a separate manifests/loadgenerator.yaml file.
# Callers are responsible for checking whether loadgenerator already exists
# first; this always applies, it does not itself check-before-deploy.
deploy_loadgenerator() {
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgenerator
  namespace: ${NAMESPACE}
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
}

# Check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' not found. Please deploy the application first."
        exit 1
    fi
}

# Check and optionally deploy load generator
check_load_generator() {
    if kubectl get deployment loadgenerator -n "$NAMESPACE" &> /dev/null; then
        REPLICAS=$(kubectl get deployment loadgenerator -n "$NAMESPACE" -o jsonpath='{.status.replicas}')
        READY=$(kubectl get deployment loadgenerator -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        
        if [ "$READY" = "$REPLICAS" ] && [ "$REPLICAS" -gt 0 ]; then
            print_success "Load generator is running ($READY/$REPLICAS replicas)"
            return 0
        else
            print_warning "Load generator exists but not ready ($READY/$REPLICAS replicas)"
            return 1
        fi
    else
        print_warning "Load generator is NOT deployed"
        echo ""
        echo "Most scenarios require traffic to be observable in Grafana."
        echo "Without the load generator, you won't see much activity."
        echo ""
        read -p "Would you like to deploy the load generator now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Deploying load generator..."
            deploy_loadgenerator
            echo "Waiting for load generator to start..."
            sleep 10
            kubectl get pods -n "$NAMESPACE" -l app=loadgenerator
            print_success "Load generator deployed!"
            echo ""
            read -p "Press Enter to continue..."
        else
            echo "Continuing without load generator..."
            echo "Note: Some scenarios may not be visible in Grafana without traffic."
        fi
        return 1
    fi
}

# Scenario 1: Deployment Failure (Pod CrashLoopBackOff)
scenario_1() {
    print_header "Scenario 1: Deployment Failure (CrashLoopBackOff)"
    echo "This simulates a deployment with a broken container image."
    echo "Effect: Pod will fail to start, showing CrashLoopBackOff status"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Breaking recommendationservice deployment..."
    
    # Change image to non-existent version
    kubectl patch deployment recommendationservice -n "$NAMESPACE" --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "gcr.io/google-samples/microservices-demo/recommendationservice:broken-v999"}]'
    
    print_success "Scenario applied!"
    echo ""
    echo "To observe:"
    echo "  kubectl get pods -n $NAMESPACE -l app=recommendationservice"
    echo "  kubectl describe pod -n $NAMESPACE -l app=recommendationservice"
    echo ""
    echo "In Grafana:"
    echo "  - Check pod status metrics"
    echo "  - View logs showing ImagePullBackOff errors"
    echo "  - Service will show as unavailable"
}

# Scenario 2: Resource Exhaustion (OOMKilled)
scenario_2() {
    print_header "Scenario 2: Resource Exhaustion (OOMKilled)"
    echo "This simulates a service running out of memory."
    echo "Effect: Pod will be killed by Kubernetes OOM killer"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Setting very low memory limit on cartservice..."

    # Set extremely low memory limit (request must stay <= limit or the patch is rejected)
    kubectl patch deployment cartservice -n "$NAMESPACE" --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "10Mi"}, {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "8Mi"}]'
    
    print_success "Scenario applied!"
    echo ""
    echo "To observe:"
    echo "  kubectl get pods -n $NAMESPACE -l app=cartservice -w"
    echo "  kubectl describe pod -n $NAMESPACE -l app=cartservice"
    echo ""
    echo "In Grafana:"
    echo "  - Memory usage metrics will spike"
    echo "  - Pod restart count will increase"
    echo "  - OOMKilled events in logs"
}

# Scenario 3: Service Unavailable (Scale to Zero)
scenario_3() {
    print_header "Scenario 3: Service Unavailable (Scaled to Zero)"
    echo "This simulates a service being completely unavailable."
    echo "Effect: All requests to the service will fail"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Scaling productcatalogservice to 0 replicas..."
    
    kubectl scale deployment productcatalogservice -n "$NAMESPACE" --replicas=0
    
    print_success "Scenario applied!"
    echo ""
    echo "To observe:"
    echo "  kubectl get pods -n $NAMESPACE -l app=productcatalogservice"
    echo ""
    echo "In Grafana:"
    echo "  - Service will show 0 pods running"
    echo "  - Error rate will spike to 100%"
    echo "  - Traces will show connection refused errors"
    echo "  - Frontend will show 'product catalog unavailable' errors"
}

# Scenario 4: Slow Service (CPU Throttling)
scenario_4() {
    print_header "Scenario 4: Slow Service (CPU Throttling)"
    echo "This simulates a service with insufficient CPU resources."
    echo "Effect: Service will be slow due to CPU throttling"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Setting very low CPU limit on checkoutservice..."
    
    # Set extremely low CPU limit
    kubectl patch deployment checkoutservice -n "$NAMESPACE" --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/resources/limits", "value": {"cpu": "10m"}}]'
    
    print_success "Scenario applied!"
    echo ""
    echo "To observe:"
    echo "  kubectl top pods -n $NAMESPACE -l app=checkoutservice"
    echo ""
    echo "In Grafana:"
    echo "  - CPU throttling metrics will show"
    echo "  - Request latency will increase significantly"
    echo "  - Traces will show slow spans"
}

# Scenario 5: Network Issues (Pod Deletion Loop)
scenario_5() {
    print_header "Scenario 5: Network Issues (Pod Instability)"
    echo "This simulates intermittent network issues by repeatedly deleting pods."
    echo "Effect: Pods will restart frequently, causing connection errors"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Starting pod deletion loop for shippingservice..."
    echo "This will delete the pod every 30 seconds for 3 minutes."
    echo "Press Ctrl+C to stop early."
    echo ""
    
    for i in {1..6}; do
        echo "Iteration $i/6: Deleting shippingservice pod..."
        kubectl delete pod -n "$NAMESPACE" -l app=shippingservice
        if [ $i -lt 6 ]; then
            echo "Waiting 30 seconds..."
            sleep 30
        fi
    done
    
    print_success "Scenario completed!"
    echo ""
    echo "In Grafana:"
    echo "  - Pod restart count will increase"
    echo "  - Intermittent connection errors in traces"
    echo "  - Error rate will spike during restarts"
}

# Scenario 6: Database Connection Issues (Redis Unavailable)
scenario_6() {
    print_header "Scenario 6: Database Connection Issues"
    echo "This simulates database/cache unavailability."
    echo "Effect: Services depending on Redis will fail"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Scaling redis-cart to 0 replicas..."
    
    kubectl scale deployment redis-cart -n "$NAMESPACE" --replicas=0
    
    print_success "Scenario applied!"
    echo ""
    echo "To observe:"
    echo "  kubectl get pods -n $NAMESPACE -l app=redis-cart"
    echo ""
    echo "In Grafana:"
    echo "  - cartservice will show connection errors"
    echo "  - Error logs: 'could not connect to redis'"
    echo "  - Traces will show failed Redis operations"
    echo "  - Shopping cart functionality will fail"
}

# Scenario 7: High Load (Scale Up Load Generator)
scenario_7() {
    print_header "Scenario 7: High Load Simulation"
    echo "This increases the load generator to create high traffic."
    echo "Effect: System will experience high request rates"
    echo ""
    
    # Check if load generator exists
    if ! kubectl get deployment loadgenerator -n "$NAMESPACE" &> /dev/null; then
        print_error "Load generator not deployed. Deploy it first from option 10 (Manage Load Generator)."
        return
    fi
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Scaling load generator to 5 replicas..."
    
    kubectl scale deployment loadgenerator -n "$NAMESPACE" --replicas=5
    
    print_success "Scenario applied!"
    echo ""
    echo "To observe:"
    echo "  kubectl get pods -n $NAMESPACE -l app=loadgenerator"
    echo ""
    echo "In Grafana:"
    echo "  - Request rate will increase 5x"
    echo "  - Resource usage will increase"
    echo "  - May trigger autoscaling if configured"
    echo "  - Latency may increase under load"
}

# Scenario 8: Restore All Services
restore_all() {
    print_header "Scenario 8: Restore All Services to Normal"
    echo "This will restore all services to their normal state."
    echo ""
    
    read -p "Restore all services? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Restoring all services..."
    
    # Delete all deployments and redeploy from clean manifests
    echo "Deleting all deployments..."
    kubectl delete deployment --all -n "$NAMESPACE"
    
    echo "Waiting for cleanup..."
    sleep 5
    
    echo "Redeploying from clean manifests..."
    cd "$SCRIPT_DIR"
    bash deploy-all-in-one-local.sh
    
    print_success "All services restored!"
    echo ""
    echo "Verify with:"
    echo "  kubectl get pods -n $NAMESPACE"
}

# Scenario 9: Multiple Cascading Failures
scenario_9() {
    print_header "Scenario 9: Cascading Failures"
    echo "This simulates multiple services failing in sequence."
    echo "Effect: Demonstrates how failures cascade through the system"
    echo ""
    
    read -p "Apply this scenario? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_warning "Starting cascading failure scenario..."
    
    echo "Step 1: Scaling down redis-cart..."
    kubectl scale deployment redis-cart -n "$NAMESPACE" --replicas=0
    sleep 10
    
    echo "Step 2: Scaling down productcatalogservice..."
    kubectl scale deployment productcatalogservice -n "$NAMESPACE" --replicas=0
    sleep 10
    
    echo "Step 3: Setting low memory on cartservice..."
    kubectl patch deployment cartservice -n "$NAMESPACE" --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "10Mi"}, {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "8Mi"}]'
    
    print_success "Cascading failure scenario applied!"
    echo ""
    echo "In Grafana:"
    echo "  - Watch how errors propagate through the system"
    echo "  - Multiple services will show errors"
    echo "  - Traces will show the failure chain"
    echo "  - Error rate will increase across multiple services"
}

# Scenario 10: Manage Load Generator
scenario_10() {
    print_header "Scenario 10: Manage Load Generator"
    
    if kubectl get deployment loadgenerator -n "$NAMESPACE" &> /dev/null; then
        REPLICAS=$(kubectl get deployment loadgenerator -n "$NAMESPACE" -o jsonpath='{.status.replicas}')
        READY=$(kubectl get deployment loadgenerator -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        echo "Current status: $READY/$REPLICAS replicas ready"
        echo ""
        echo "Options:"
        echo "  1) Scale to 1 replica (~20 req/s)"
        echo "  2) Scale to 2 replicas (~40 req/s)"
        echo "  3) Scale to 5 replicas (~100 req/s)"
        echo "  4) Stop load generator (scale to 0)"
        echo "  5) Delete load generator"
        echo "  0) Back to main menu"
        echo ""
        read -p "Choose option: " choice
        
        case $choice in
            1) kubectl scale deployment loadgenerator -n "$NAMESPACE" --replicas=1 && print_success "Scaled to 1 replica" ;;
            2) kubectl scale deployment loadgenerator -n "$NAMESPACE" --replicas=2 && print_success "Scaled to 2 replicas" ;;
            3) kubectl scale deployment loadgenerator -n "$NAMESPACE" --replicas=5 && print_success "Scaled to 5 replicas" ;;
            4) kubectl scale deployment loadgenerator -n "$NAMESPACE" --replicas=0 && print_success "Load generator stopped" ;;
            5)
                read -p "Are you sure you want to delete the load generator? (y/n) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    kubectl delete deployment loadgenerator -n "$NAMESPACE"
                    print_success "Load generator deleted"
                fi
                ;;
            0) return ;;
            *) print_error "Invalid choice" ;;
        esac
    else
        echo "Load generator is not deployed."
        echo ""
        read -p "Would you like to deploy it now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            deploy_loadgenerator
            echo "Waiting for load generator to start..."
            sleep 10
            kubectl get pods -n "$NAMESPACE" -l app=loadgenerator
            print_success "Load generator deployed!"
        fi
    fi
}

# Main menu
show_menu() {
    print_header "Online Boutique - Error Simulation Scenarios"
    echo "Choose a scenario to simulate:"
    echo ""
    echo "  1) Deployment Failure (CrashLoopBackOff)"
    echo "  2) Resource Exhaustion (OOMKilled)"
    echo "  3) Service Unavailable (Scale to Zero)"
    echo "  4) Slow Service (CPU Throttling)"
    echo "  5) Network Issues (Pod Instability)"
    echo "  6) Database Connection Issues"
    echo "  7) High Load Simulation"
    echo "  8) Restore All Services"
    echo "  9) Cascading Failures"
    echo " 10) Manage Load Generator"
    echo "  0) Exit"
    echo ""
}

# Main execution
main() {
    check_namespace
    
    # Check load generator status
    echo ""
    check_load_generator
    echo ""
    
    while true; do
        show_menu
        read -p "Enter scenario number: " choice
        
        case $choice in
            1) scenario_1 ;;
            2) scenario_2 ;;
            3) scenario_3 ;;
            4) scenario_4 ;;
            5) scenario_5 ;;
            6) scenario_6 ;;
            7) scenario_7 ;;
            8) restore_all ;;
            9) scenario_9 ;;
            10) scenario_10 ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please try again."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main
