#!/bin/bash
# cka-prep.sh - CKA-PREP-2025-v2 practice labs (19 tasks) in ONE file for Killercoda.
# Based on github.com/markdjones82/CKA-PREP-2025-v2 (same numbering as the HTML),
# with bug fixes in setup/validate/cleanup (see FIXES at the end of this file).
#
#   cka list            # list all tasks
#   cka setup 5         # create the lab + print the task
#   cka question 5      # print the task again
#   cka check 5         # validate your answer   (check all = every task)
#   cka solution 5      # show the solution
#   cka cleanup 5       # remove the lab
#   (first time: bash cka-prep.sh  -> installs the command 'cka' in /usr/local/bin)
set -uo pipefail
LAB_DIR="${CKA_DIR:-$HOME/.cka-prep}"
TITLE=(
  ''
  'MariaDB Persistent volume'
  'ArgoCD'
  'Sidecar'
  'Resource Allocation'
  'HPA'
  'CRDs'
  'PriorityClass'
  'CNI Network Policy'
  'Cri Dockerd'
  'Taints Tolerations'
  'Gateway API'
  'Ingress'
  'Network Policy'
  'Storage Class'
  'Etcd Fix'
  'NodePort'
  'TLS Config'
  'Kubectl Patch'
  'Resource Allocation v2'
)

# ---- embedded lab files (written to $LAB_DIR/qN/) ----
extract() {
mkdir -p "$LAB_DIR/q1"
cat > "$LAB_DIR/q1/setup.bash" <<'__CKA_Q1_SETUP__'
#!/bin/bash
set -e

echo "Creating namespace..."
kubectl create ns mariadb --dry-run=client -o yaml | kubectl apply -f -

# Query for default storage class to ensure PV uses correct class for binding
default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [ -z "$default_sc" ]; then
  default_sc="standard"
  echo "No default StorageClass detected, using 'standard' as fallback."
else
  echo "Default StorageClass detected: $default_sc"
fi
echo "Creating PersistentVolume..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
  labels:
    app: mariadb
spec:
  capacity:
    storage: 250Mi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $default_sc  # Use default or fallback storage class so PVC without storageClassName binds
  hostPath:
    path: /mnt/data/mariadb
EOF

echo "Creating initial PVC..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
EOF

echo "Creating initial MariaDB Deployment..."
cat <<EOF > ~/mariadb-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.6
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpass
        volumeMounts:
        - name: mariadb-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-storage
        persistentVolumeClaim:
          claimName: mariadb
EOF

kubectl apply -f ~/mariadb-deploy.yaml

echo "Waiting for MariaDB pod to start..."
kubectl wait --for=condition=Available deployment/mariadb -n mariadb --timeout=60s || true

echo "Simulating accidental deletion of Deployment and PVC..."
kubectl delete deployment mariadb -n mariadb --ignore-not-found
kubectl delete pvc mariadb -n mariadb --ignore-not-found

echo "Resetting PV for reuse (clearing any stale claimRef)..."
claim_ref=$(kubectl get pv mariadb-pv -o jsonpath='{.spec.claimRef.name}' 2>/dev/null || true)
if [ -n "$claim_ref" ]; then
  kubectl patch pv mariadb-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
fi

# Refresh the deployment manifest for practice: claimName intentionally left blank
cat <<'EOF' > ~/mariadb-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.6
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpass
        volumeMounts:
        - name: mariadb-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-storage
        persistentVolumeClaim:
          claimName: ""
EOF

echo "[OK] Lab setup complete!"
echo "   - PV retained and ready for reuse"
echo "   - Namespace: mariadb"
echo "   - Task: recreate PVC and deployment reusing existing PV (fill claimName in ~/mariadb-deploy.yaml)"
__CKA_Q1_SETUP__
cat > "$LAB_DIR/q1/question.bash" <<'__CKA_Q1_QUESTION__'
# Question:
# A user accidentally deleted the MariaDB Deployment in the mariadb namespace. The deployment
# was configured with persistent storage. Your responsibility is to re-establish the deployment
# while ensuring data is preserved by reusing the available PersistentVolume

#Task
# A PersistentVolume already exists and is retained for reuse. Only one PV exists
# Create a Persistent Volume Claim (PVC) named mariadb in the mariadb namespace with the spec
# Access Mode = ReadWriteOnce
# Storage = 250Mi
# Edit the MariaDb Deployment file located at ~/mariadb-deploy.yaml to use the PVC created in the previous step
# Apply the updated Deployment file to the cluster
# Ensure the MariaDB Deployment is running and Stable

#Video Link - https://youtu.be/aXvvc1EB1zg

#Documentation Reference
# Tip: Navigate the documentation manually to build familiarity with its structure
# Concepts -> Storage -> Persistent Volumes
# https://kubernetes.io/docs/concepts/storage/persistent-volumes/
__CKA_Q1_QUESTION__
cat > "$LAB_DIR/q1/check.bash" <<'__CKA_Q1_CHECK__'
#!/bin/bash
# Validation script for Question 1 - MariaDB Persistent Volume
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 1: MariaDB PV"
echo "======================================"

# 1. PVC named mariadb exists in mariadb namespace
check "PVC 'mariadb' exists in namespace 'mariadb'" \
  kubectl get pvc mariadb -n mariadb

# 2. PVC access mode is ReadWriteOnce
check "PVC access mode is ReadWriteOnce" \
  bash -c '[[ "$(kubectl get pvc mariadb -n mariadb -o jsonpath="{.spec.accessModes[0]}")" == "ReadWriteOnce" ]]'

# 3. PVC storage request is 250Mi
check "PVC storage request is 250Mi" \
  bash -c '[[ "$(kubectl get pvc mariadb -n mariadb -o jsonpath="{.spec.resources.requests.storage}")" == "250Mi" ]]'

# 4. PVC is Bound
check "PVC is in Bound state" \
  bash -c '[[ "$(kubectl get pvc mariadb -n mariadb -o jsonpath="{.status.phase}")" == "Bound" ]]'

# 5. PV mariadb-pv is Bound
check "PV 'mariadb-pv' is Bound" \
  bash -c '[[ "$(kubectl get pv mariadb-pv -o jsonpath="{.status.phase}")" == "Bound" ]]'

# 6. Deployment mariadb exists in mariadb namespace
check "Deployment 'mariadb' exists in namespace 'mariadb'" \
  kubectl get deployment mariadb -n mariadb

# 7. Deployment references the PVC mariadb
check "Deployment uses PVC 'mariadb'" \
  bash -c '[[ "$(kubectl get deployment mariadb -n mariadb -o jsonpath="{.spec.template.spec.volumes[0].persistentVolumeClaim.claimName}")" == "mariadb" ]]'

# 8. Deployment is available (at least 1 ready replica)
check "Deployment has at least 1 available replica" \
  bash -c '[[ $(kubectl get deployment mariadb -n mariadb -o jsonpath="{.status.availableReplicas}") -ge 1 ]]'

# 9. Pod is Running
check "MariaDB pod is Running" \
  bash -c 'kubectl get pods -n mariadb -l app=mariadb -o jsonpath="{.items[0].status.phase}" | grep -q Running'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q1_CHECK__
cat > "$LAB_DIR/q1/cleanup.bash" <<'__CKA_Q1_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 1 - MariaDB Persistent Volume
set -uo pipefail
echo "Cleaning up Question 1: MariaDB Persistent Volume..."

kubectl delete deployment mariadb -n mariadb --ignore-not-found
kubectl delete pvc mariadb -n mariadb --ignore-not-found
kubectl delete pv mariadb-pv --ignore-not-found
kubectl delete namespace mariadb --ignore-not-found
rm -f ~/mariadb-deploy.yaml ~/pvc.yaml

echo "[OK] Question 1 cleanup complete"
__CKA_Q1_CLEANUP__
cat > "$LAB_DIR/q1/solution.bash" <<'__CKA_Q1_SOLUTION__'
# Step 1: create PVC. There are 2 ways to do this. (PV is pre-reset by LabSetUp.bash)
cat <<'EOF' > pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
  - ReadWriteOnce
  volumeName: mariadb-pv  # bind to specific PV. This is optional but ensures we know which PV is used. If left blank, PVC will bind to any available PV that matches access modes and storage class.
  resources:
    requests:
      storage: 250Mi
  storageClassName: # Set this to the default storage class name. Some are "standard" some "local-path" etc. Check with "kubectl get storageclass". 
                    # If you used volumeName above, storageClassName can be left blank and it will bind to the PV by name. If you leave volumeName blank, then storageClassName must match the PV's storageClassName for binding to occur.
EOF
kubectl apply -f pvc.yaml
kubectl get pvc mariadb -n mariadb
kubectl get pv mariadb-pv     # should show Bound to mariadb

# Step 2: ensure deployment uses the PVC
# mariadb-deploy.yaml should mount claimName: mariadb
# (LabSetUp.bash leaves claimName blank for practice)
kubectl apply -f mariadb-deploy.yaml
kubectl get pods -n mariadb
__CKA_Q1_SOLUTION__
mkdir -p "$LAB_DIR/q2"
cat > "$LAB_DIR/q2/setup.bash" <<'__CKA_Q2_SETUP__'
#!/bin/bash
echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"
__CKA_Q2_SETUP__
cat > "$LAB_DIR/q2/question.bash" <<'__CKA_Q2_QUESTION__'
# Question ArgoCD

#Task
# Install Argo CD in a kubernetes cluster using helm while ensuring the CRDs are not installed
# (as they are pre installed)
# 1. Add the official Argo CD Helm repository with the name argocd (https://argoproj.github.io/argo-helm)
# 2. Create a namespace called argocd
# 3. Generate a Helm template from the Argo CD chart version 7.7.3 for the argocd namespace
# 4. Ensure that CRDs are not installed by configuring the chart accordingly
# 5. Save the generated YAML manifest to /root/argo-helm.yaml

# Note: The `--skip-crds` Helm flag does NOT reliably prevent CRD installation for all charts.
# Some charts (like argo-cd) bundle CRDs as regular templates controlled by a chart value. 
# Hint search for the crds value in the argo-cd chart and set it to false to prevent CRD installation.

# Video link - https://youtu.be/e0YGRSjb8CU
__CKA_Q2_QUESTION__
cat > "$LAB_DIR/q2/check.bash" <<'__CKA_Q2_CHECK__'
#!/bin/bash
# Validation script for Question 2 - ArgoCD Helm Template
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 2: ArgoCD"
echo "======================================"

# 1. Namespace argocd exists
check "Namespace 'argocd' exists" \
  kubectl get namespace argocd

# 2. Helm repo argocd exists
check "Helm repo 'argocd' is added" \
  bash -c 'helm repo list 2>/dev/null | grep -q "argocd"'

# 3. Helm repo points to correct URL
check "Helm repo URL is correct (argoproj.github.io/argo-helm)" \
  bash -c 'helm repo list 2>/dev/null | grep argocd | grep -q "https://argoproj.github.io/argo-helm"'

# 4. /root/argo-helm.yaml exists
check "File /root/argo-helm.yaml exists" \
  test -f /root/argo-helm.yaml

# 5. /root/argo-helm.yaml is not empty
check "File /root/argo-helm.yaml is not empty" \
  test -s /root/argo-helm.yaml

# 6. The generated manifest references argocd namespace
check "Manifest references argocd namespace" \
  bash -c 'grep -q "namespace.*argocd\|argocd" /root/argo-helm.yaml'

# 6b. Template was generated from chart version 7.7.3
check "Manifest generated from chart argo-cd-7.7.3" \
  bash -c 'grep -q "helm.sh/chart: argo-cd-7.7.3" /root/argo-helm.yaml'

# 7. No CRD resources in the generated YAML
check "No CRD kind in generated manifest (CRDs skipped)" \
  bash -c '! grep -q "kind: CustomResourceDefinition" /root/argo-helm.yaml'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q2_CHECK__
cat > "$LAB_DIR/q2/cleanup.bash" <<'__CKA_Q2_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 2 - ArgoCD
set -uo pipefail
echo "Cleaning up Question 2: ArgoCD..."

helm uninstall argocd -n argocd 2>/dev/null || true
kubectl delete namespace argocd --ignore-not-found
helm repo remove argocd 2>/dev/null || true
rm -f /root/argo-helm.yaml ~/argo-helm.yaml

echo "[OK] Question 2 cleanup complete"
__CKA_Q2_CLEANUP__
cat > "$LAB_DIR/q2/solution.bash" <<'__CKA_Q2_SOLUTION__'
# Create namespace
kubectl create namespace argocd

# Add repo and template manifests (CRDs not installed)
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo update

# To get the crd value to change, you can run: helm show values argocd/argo-cd --version 7.7.3 | grep -i crd -C 4

# The task only asks for a template - no helm install needed.
helm template argocd argocd/argo-cd --version 7.7.3 --set crds.install=false --namespace argocd > /root/argo-helm.yaml
cat /root/argo-helm.yaml   # confirm output


#Additional helm tips:
# To list all versions of a chart: helm search repo argocd/argo-cd --versions
# To show values of a chart: helm show values argocd/argo-cd --version 7.7.3
__CKA_Q2_SOLUTION__
mkdir -p "$LAB_DIR/q3"
cat > "$LAB_DIR/q3/setup.bash" <<'__CKA_Q3_SETUP__'
#!/bin/bash
set -e

echo "Setting up WordPress deployment for sidecar lab in the default namespace..."

# 1. Create WordPress deployment without log volume
cat <<EOF | kubectl apply -n default -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: default
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        command: ["/bin/sh", "-c", "while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done"]
        ports:
        - containerPort: 80
EOF

# 2. Create a service to expose the deployment
cat <<EOF | kubectl apply -n default -f -
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: default
spec:
  selector:
    app: wordpress
  ports:
  - port: 80
    targetPort: 80
EOF

echo
echo "[OK] Lab setup complete!"
echo
echo "WordPress deployment created in the default namespace."
echo "You can now edit the deployment to add the sidecar container and shared volume."
__CKA_Q3_SETUP__
cat > "$LAB_DIR/q3/question.bash" <<'__CKA_Q3_QUESTION__'
# Question SideCar

# Task
# Update the existing wordpress deployment adding a sidecar container named sidecar using the busybox:stable
# image to the existing pod
# The new sidecar container has to run the following command (as given by the exam task):
"/bin/sh -c tail -f /var/log/wordpress.log"
# Note: In your solution use `tail -F` (capital F) – it follows log files across
# rotation and re-creation, whereas `-f` (lowercase) can miss logs after rotation.

#Video link - https://youtu.be/3xraEGGQJDY

#Documentation Reference
# Tip: Navigate the documentation manually to build familiarity with its structure
# Concepts -> Workloads -> pod -> Sidecar Containers
# https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/
__CKA_Q3_QUESTION__
cat > "$LAB_DIR/q3/check.bash" <<'__CKA_Q3_CHECK__'
#!/bin/bash
# Validation script for Question 3 - Sidecar Container
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 3: Sidecar"
echo "======================================"

# 1. Deployment wordpress exists
check "Deployment 'wordpress' exists" \
  bash -c 'kubectl get deployment wordpress -n default -o name | grep -q "^deployment.apps/wordpress$"'

# 2. Deployment is available
check "WordPress deployment has available replicas" \
  bash -c '[[ $(kubectl get deployment wordpress -n default -o jsonpath="{.status.availableReplicas}" 2>/dev/null) -ge 1 ]]'

# 3. Sidecar container named sidecar exists with busybox:stable image
check "Sidecar container named sidecar exists" \
  bash -c '
    IMG=$(kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.containers[?(@.name==\"sidecar\")].image}{.spec.template.spec.initContainers[?(@.name==\"sidecar\")].image}" 2>/dev/null)
    [[ "$IMG" == "busybox:stable" ]]
  '

# 4. The sidecar runs tail -f or tail -F on /var/log/wordpress.log
check "Sidecar runs tail on /var/log/wordpress.log" \
  bash -c '
    CMD=$(kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.containers[?(@.name==\"sidecar\")].command[*]}" 2>/dev/null)
    if [[ -z "$CMD" ]]; then
      CMD=$(kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.initContainers[?(@.name==\"sidecar\")].command[*]}" 2>/dev/null)
    fi
    [[ "$CMD" == *"tail"* && "$CMD" == *"wordpress.log"* ]]
  '

# 5. Shared volume exists (emptyDir) - volume name can be anything
check "Shared emptyDir volume configured" \
  bash -c '
    V=$(kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.volumes[?(@.emptyDir)].name}")
    [[ -n "$V" ]]
  '

# 6. Volume mounted at /var/log on main container
check "Volume mounted at /var/log on main container" \
  bash -c '
    kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.containers[?(@.name==\"wordpress\")].volumeMounts[?(@.mountPath==\"/var/log\")].mountPath}" | grep -q "^/var/log$"
  '

# 7. Volume mounted at /var/log on sidecar or init container
check "Volume mounted at /var/log on sidecar" \
  bash -c '
    MOUNT=$(kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.containers[?(@.name==\"sidecar\")].volumeMounts[?(@.mountPath==\"/var/log\")].mountPath}" 2>/dev/null)
    if [[ -z "$MOUNT" ]]; then
      MOUNT=$(kubectl get deployment wordpress -n default -o jsonpath="{.spec.template.spec.initContainers[?(@.name==\"sidecar\")].volumeMounts[?(@.mountPath==\"/var/log\")].mountPath}" 2>/dev/null)
    fi
    [[ "$MOUNT" == "/var/log" ]]
  '

# 8. WordPress log line exists in the shared volume
check "WordPress log line is written to shared volume" \
  bash -c '
    POD=$(kubectl get pods -n default -l app=wordpress -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    [[ -n "$POD" ]] || exit 1
    kubectl exec "$POD" -n default -c wordpress -- sh -c "grep -q \"WordPress is running...\" /var/log/wordpress.log"
  '

# 9. Pod is running
check "WordPress pod is Running" \
  bash -c 'kubectl get pods -n default -l app=wordpress -o jsonpath="{.items[0].status.phase}" | grep -q "^Running$"'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q3_CHECK__
cat > "$LAB_DIR/q3/cleanup.bash" <<'__CKA_Q3_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 3 - Sidecar
set -uo pipefail
echo "Cleaning up Question 3: Sidecar..."

kubectl delete deployment wordpress -n default --ignore-not-found
kubectl delete service wordpress -n default --ignore-not-found 2>/dev/null || true

echo "[OK] Question 3 cleanup complete"
__CKA_Q3_CLEANUP__
cat > "$LAB_DIR/q3/solution.bash" <<'__CKA_Q3_SOLUTION__'
# Solution Link for documentation: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/#jobs-with-sidecar-containers

# Sidecar notes:
# 1) Exam-preferred solution: Co-located container pattern (n + 1 containers).
#    - Add a regular container alongside the main app container in the same pod.
#    - This is the approach the CKA exam expects for Deployments.
#    - Use `tail -F` (capital F) instead of `tail -f` (lowercase):
#      - `-F` follows log files across rotation and re-creation.
#      - `-f` can miss logs after rotation.
# 2) To verify the shared log volume is mounted:
#    - write or confirm a line like `WordPress is running...` in /var/log/wordpress.log
#    - then check the same file from the other container with `kubectl exec`
#    - if both containers can see the same line, the volume is mounted and shared

# ─────────────────────────────────────────────────────────────────────────────
# EXAM-PREFERRED SOLUTION: Co-located sidecar container (n + 1 pattern)
# ─────────────────────────────────────────────────────────────────────────────
# The exam expects a regular co-located container (not an initContainer) added
# to the Deployment.  Use kubectl edit or apply a full manifest with -f.

# Option A – kubectl edit (imperative, fastest in exam conditions):
k edit deployments wordpress
# The existing wordpress container already runs the log-writing command in this lab,
# so you only need to add three things:
#   1. A shared volume under spec.template.spec
#   2. A volumeMount for the existing wordpress container
#   3. The new co-located sidecar container
#
#   spec:
#     volumes:
#     - name: logs
#       emptyDir: {}
#     containers:
#     - name: wordpress          # existing container – add volumeMounts here
#       ...
#       volumeMounts:
#       - name: logs
#         mountPath: /var/log
#     - name: sidecar            # new co-located container
#       image: busybox:stable
#       command: ['sh', '-c', 'tail -F /var/log/wordpress.log']
#       volumeMounts:
#       - name: logs
#         mountPath: /var/log

# Option B – apply a full manifest with kubectl apply -f (declarative):
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      volumes:
      - name: logs
        emptyDir: {}
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        ports:
        - containerPort: 80
        command:
        - /bin/sh
        - -c
        - while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done
        volumeMounts:
        - name: logs
          mountPath: /var/log
      - name: sidecar
        image: busybox:stable
        command: ['sh', '-c', 'tail -F /var/log/wordpress.log']
        volumeMounts:
        - name: logs
          mountPath: /var/log
EOF

kubectl rollout status deployment wordpress
kubectl get pods -l app=wordpress


# Manual verification commands:
# 1) Confirm the Pod and containers are running
kubectl get pods -l app=wordpress -o wide
kubectl describe pod -l app=wordpress

# 2) Confirm the shared log file contains the app output
POD=$(kubectl get pods -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -c wordpress -- sh -c 'cat /var/log/wordpress.log | tail'

# 3) Confirm the sidecar can see the same file
kubectl exec "$POD" -c sidecar -- sh -c 'cat /var/log/wordpress.log | tail'

# 4) Optional: verify the mounted path inside both containers
kubectl exec "$POD" -c wordpress -- sh -c 'mount | grep /var/log'
kubectl exec "$POD" -c sidecar -- sh -c 'mount | grep /var/log'


# ─────────────────────────────────────────────────────────────────────────────
# FOR REFERENCE / LEARNING ONLY: InitContainer sidecar pattern
# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes 1.29+ introduced native sidecar support via initContainers with
# restartPolicy: Always.  This is useful for Jobs (where regular containers
# would keep the Job alive), but the CKA exam for Deployment tasks expects the
# co-located container approach above.  This section is provided for learning.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      volumes:
      - name: logs
        emptyDir: {}
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        ports:
        - containerPort: 80
        command:
        - /bin/sh
        - -c
        - while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done
        volumeMounts:
        - name: logs
          mountPath: /var/log
      initContainers:
      - name: sidecar
        image: busybox:stable
        restartPolicy: Always
        command: ['sh', '-c', 'tail -F /var/log/wordpress.log']
        volumeMounts:
        - name: logs
          mountPath: /var/log
EOF
__CKA_Q3_SOLUTION__
mkdir -p "$LAB_DIR/q4"
cat > "$LAB_DIR/q4/setup.bash" <<'__CKA_Q4_SETUP__'
#!/bin/bash
# setup-wordpress.sh
# Create a WordPress deployment with 3 replicas and an init container

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      initContainers:
      - name: init-setup
        image: busybox
        command: ["sh", "-c", "echo 'Preparing environment...' && sleep 5"]
      containers:
      - name: wordpress
        image: wordpress:6.2-apache
        ports:
        - containerPort: 80
EOF
__CKA_Q4_SETUP__
cat > "$LAB_DIR/q4/question.bash" <<'__CKA_Q4_QUESTION__'
# Question
# You are managing a WordPress application running in a Kubernetes cluster
# Your task is to adjust the Pod resource requests and limits to ensure stable operation

# Tasks
# 1. Scale down the wordpress deployment to 0 replicas
# 2. Edit the deployment and divide the node resource evenly across all 3 pods
# 3. Assign fair and equal CPU and memory to each Pod
# 4. Add sufficient overhead to avoid node instability
# Ensure both the init containers and the main containers use exactly the same resource requests and limits
# After making the changes scale the deployment back to 3 replicas

#Video link - https://youtu.be/ZqGDdETii8c

#Documentation Reference
# Tip: Navigate the documentation manually to build familiarity with its structure
# Concepts -> Configuration -> Resource Management for Pods and Containers
# https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
__CKA_Q4_QUESTION__
cat > "$LAB_DIR/q4/check.bash" <<'__CKA_Q4_CHECK__'
#!/bin/bash
# Validation script for Question 4 - Resource Allocation
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "==========================================="
echo " Validating Question 4: Resource Allocation"
echo "==========================================="

# 1. Deployment wordpress exists
check "Deployment 'wordpress' exists" \
  kubectl get deployment wordpress

# 2. Deployment is scaled to 3 replicas
check "Deployment has 3 replicas" \
  bash -c '[[ "$(kubectl get deployment wordpress -o jsonpath="{.spec.replicas}")" == "3" ]]'

# 3. All 3 pods are available
check "All 3 replicas are available" \
  bash -c '[[ $(kubectl get deployment wordpress -o jsonpath="{.status.availableReplicas}" 2>/dev/null) -ge 3 ]]'

# 4. Main containers have resource requests defined
check "Main containers have CPU requests set" \
  bash -c '
    REQ=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].resources.requests.cpu}" 2>/dev/null)
    [[ -n "$REQ" ]]
  '

check "Main containers have memory requests set" \
  bash -c '
    REQ=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].resources.requests.memory}" 2>/dev/null)
    [[ -n "$REQ" ]]
  '

# 5. Main containers have resource limits defined
check "Main containers have CPU limits set" \
  bash -c '
    LIM=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].resources.limits.cpu}" 2>/dev/null)
    [[ -n "$LIM" ]]
  '

check "Main containers have memory limits set" \
  bash -c '
    LIM=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].resources.limits.memory}" 2>/dev/null)
    [[ -n "$LIM" ]]
  '

# 6. Init containers (if any) have the same resources as main containers
check "Init containers have matching resource requests/limits (if present)" \
  bash -c '
    HAS_INIT=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.initContainers[0].name}" 2>/dev/null)
    # If no init containers, pass
    if [[ -z "$HAS_INIT" ]]; then exit 0; fi
    INIT=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.initContainers[0].resources}" 2>/dev/null)
    MAIN=$(kubectl get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].resources}" 2>/dev/null)
    [[ -n "$INIT" && "$INIT" == "$MAIN" ]]
  '

# 7. All pods are Running
check "All wordpress pods are Running" \
  bash -c '
    RUNNING=$(kubectl get pods -l app=wordpress --no-headers 2>/dev/null | grep -c Running)
    [[ $RUNNING -ge 3 ]]
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q4_CHECK__
cat > "$LAB_DIR/q4/cleanup.bash" <<'__CKA_Q4_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 4 - Resource Allocation
set -uo pipefail
echo "Cleaning up Question 4: Resource Allocation..."

kubectl delete deployment wordpress --ignore-not-found
kubectl delete service wordpress --ignore-not-found 2>/dev/null || true

echo "[OK] Question 4 cleanup complete"
__CKA_Q4_CLEANUP__
cat > "$LAB_DIR/q4/solution.bash" <<'__CKA_Q4_SOLUTION__'
# Step 0: find the node's allocatable resources
kubectl describe node | grep -A5 "Allocatable:"
# Example output:
#   Allocatable:
#     cpu:     1
#     memory:  1843520Ki
#
# Convert memory from Ki to Mi: divide by 1024
#   1843520Ki / 1024 = 1800Mi
# CPU is already in cores (1 = 1000m)

# Step 1: pause workload
kubectl scale deployment wordpress --replicas 0

# Step 2: edit deployment
kubectl edit deployment wordpress
# There are 3 pods. Each pod has 1 init container + 1 main container.
# The init container finishes BEFORE the main container starts, so they never run
# at the same time: a pod needs max(init, main), not init + main -> divide by 3.
# Also subtract what is already requested on the node (kube-proxy, CNI, coredns...):
#   kubectl describe node node01 | grep -A8 "Allocated resources"
# Example: allocatable 1000m / 1800Mi, already used ~150m / ~250Mi
#   CPU:    (1000m - 150m)  / 3 ≈ 283m -> use 250m
#   Memory: (1800Mi - 250Mi) / 3 ≈ 516Mi -> use 500Mi
#
# resources:
#   requests:
#     cpu: "250m"
#     memory: "500Mi"
#   limits:
#     cpu: "250m"
#     memory: "500Mi"
# Put the SAME resources block on the init container AND the main container
# (spec.template.spec.initContainers[] and spec.template.spec.containers[])

# Step 3: resume replicas
kubectl scale deployment wordpress --replicas 3
kubectl rollout status deployment wordpress
kubectl get pods -l app=wordpress
__CKA_Q4_SOLUTION__
mkdir -p "$LAB_DIR/q5"
cat > "$LAB_DIR/q5/setup.bash" <<'__CKA_Q5_SETUP__'
#!/bin/bash
set -e

echo "Creating namespace..."
kubectl create namespace autoscale --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying metrics-server (required for HPA)..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "Patching metrics-server to allow insecure TLS (Killercoda environment)..."
kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q kubelet-insecure-tls || \
kubectl patch deployment metrics-server -n kube-system \
  --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]' || true

echo "Waiting for metrics-server rollout..."
kubectl rollout status deployment metrics-server -n kube-system

echo "Creating Apache deployment..."
kubectl apply -n autoscale -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-deployment
  namespace: autoscale
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apache
  template:
    metadata:
      labels:
        app: apache
    spec:
      containers:
      - name: apache
        image: httpd
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
          limits:
            cpu: 200m
EOF

echo "Exposing Apache deployment internally..."
kubectl expose deployment apache-deployment -n autoscale --port=80 --target-port=80 --dry-run=client -o yaml | kubectl apply -f -

echo "[OK] HPA lab setup complete."
echo "   - Namespace: autoscale"
echo "   - Deployment: apache-deployment"
echo "   - Service: apache-deployment"
echo "You can now create your HPA resource."
__CKA_Q5_SETUP__
cat > "$LAB_DIR/q5/question.bash" <<'__CKA_Q5_QUESTION__'
# Question HPA
# Create a new HorizontalPodAutoScaler(HPA) named apache-server in the autoscale namespace

# Task
# 1. The HPA must target the existing deployment called apache-deployment in the autoscale namespace
# 2. Set the HPA to target for 50% CPU usage per Pod
# 3. Configure the HPA to have a minimum of 1 pod and a maximum of 4 pods
# 4. Set the downscale stabilization window to 30 seconds

# Video Link - https://youtu.be/YGkARVFKtmM

#Documentation Reference
# Tip: Navigate the documentation manually to build familiarity with its structure
# (hpa) Tasks -> Run Application -> HorizontalPodAutoscaling Walkthrough
# https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
# (downscale) Concepts -> Workloads -> Horizontal Pod Autoscaling
# https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/
__CKA_Q5_QUESTION__
cat > "$LAB_DIR/q5/check.bash" <<'__CKA_Q5_CHECK__'
#!/bin/bash
# Validation script for Question 5 - HPA (HorizontalPodAutoscaler)
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 5: HPA"
echo "======================================"

# 1. HPA named apache-server exists in autoscale namespace
check "HPA 'apache-server' exists in namespace 'autoscale'" \
  kubectl get hpa apache-server -n autoscale

# 2. HPA targets the deployment apache-deployment
check "HPA targets deployment 'apache-deployment'" \
  bash -c '[[ "$(kubectl get hpa apache-server -n autoscale -o jsonpath="{.spec.scaleTargetRef.name}")" == "apache-deployment" ]]'

check "HPA scaleTargetRef kind is Deployment" \
  bash -c '[[ "$(kubectl get hpa apache-server -n autoscale -o jsonpath="{.spec.scaleTargetRef.kind}")" == "Deployment" ]]'

# 3. CPU target is 50%
check "HPA CPU target is 50% utilization" \
  bash -c '
    UTIL=$(kubectl get hpa apache-server -n autoscale -o jsonpath="{.spec.metrics[0].resource.target.averageUtilization}" 2>/dev/null)
    [[ "$UTIL" == "50" ]]
  '

# 4. Min replicas is 1
check "HPA minReplicas is 1" \
  bash -c '[[ "$(kubectl get hpa apache-server -n autoscale -o jsonpath="{.spec.minReplicas}")" == "1" ]]'

# 5. Max replicas is 4
check "HPA maxReplicas is 4" \
  bash -c '[[ "$(kubectl get hpa apache-server -n autoscale -o jsonpath="{.spec.maxReplicas}")" == "4" ]]'

# 6. Downscale stabilization window is 30 seconds
check "Downscale stabilizationWindowSeconds is 30" \
  bash -c '[[ "$(kubectl get hpa apache-server -n autoscale -o jsonpath="{.spec.behavior.scaleDown.stabilizationWindowSeconds}")" == "30" ]]'

# 7. Target deployment exists
check "Deployment 'apache-deployment' exists in namespace 'autoscale'" \
  kubectl get deployment apache-deployment -n autoscale

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q5_CHECK__
cat > "$LAB_DIR/q5/cleanup.bash" <<'__CKA_Q5_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 5 - HPA
set -uo pipefail
echo "Cleaning up Question 5: HPA..."

kubectl delete hpa apache-server -n autoscale --ignore-not-found
kubectl delete deployment apache-deployment -n autoscale --ignore-not-found
kubectl delete service apache-deployment -n autoscale --ignore-not-found
kubectl delete namespace autoscale --ignore-not-found
# Remove ALL metrics-server objects. Deleting only the Deployment leaves the
# v1beta1.metrics.k8s.io APIService broken, which makes later namespace deletes hang.
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found
rm -f ~/hpa.yaml

echo "[OK] Question 5 cleanup complete"
__CKA_Q5_CLEANUP__
cat > "$LAB_DIR/q5/solution.bash" <<'__CKA_Q5_SOLUTION__'
# Create HPA for apache-deployment in autoscale namespace
kubectl get deploy -n autoscale
cat <<'EOF' > hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: apache-server
  namespace: autoscale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: apache-deployment
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
EOF
kubectl apply -f hpa.yaml
kubectl get hpa -n autoscale
__CKA_Q5_SOLUTION__
mkdir -p "$LAB_DIR/q6"
cat > "$LAB_DIR/q6/setup.bash" <<'__CKA_Q6_SETUP__'
#!/bin/bash
set -e

echo "Creating namespace: cert-manager"
kubectl create ns cert-manager --dry-run=client -o yaml | kubectl apply -f -

echo "Applying cert-manager CRDs..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml

echo "Creating minimal cert-manager Deployment..."
cat <<EOF | kubectl apply -n cert-manager -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-manager
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cert-manager
  template:
    metadata:
      labels:
        app: cert-manager
    spec:
      containers:
      - name: cert-manager
        image: quay.io/jetstack/cert-manager-controller:v1.14.0
        args: ["--v=2"]
EOF

echo "[OK] Cert-Manager setup complete."
__CKA_Q6_SETUP__
cat > "$LAB_DIR/q6/question.bash" <<'__CKA_Q6_QUESTION__'
# Question CRDs

#Task
# 1. Create a list of all cert-manager [CRDs] and save it to /root/resources.yaml
# 2. Using kubectl extract the documentation for the subject specification field of the Certifciate
# Custom Resource and save it to /root/subject.yaml
# You may use any output format that kubectl supports

# Video Link - https://youtu.be/SA1DzLQaDJs
__CKA_Q6_QUESTION__
cat > "$LAB_DIR/q6/check.bash" <<'__CKA_Q6_CHECK__'
#!/bin/bash
# Validation script for Question 6 - CRDs (cert-manager)
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 6: CRDs"
echo "======================================"

# 1. /root/resources.yaml exists and is not empty
check "File /root/resources.yaml exists" \
  test -f /root/resources.yaml

check "File /root/resources.yaml is not empty" \
  test -s /root/resources.yaml

# 2. /root/resources.yaml contains cert-manager CRDs
check "/root/resources.yaml lists cert-manager CRDs" \
  bash -c 'grep -qi "cert-manager" /root/resources.yaml'

# 3. /root/subject.yaml exists and is not empty
check "File /root/subject.yaml exists" \
  test -f /root/subject.yaml

check "File /root/subject.yaml is not empty" \
  test -s /root/subject.yaml

# 4. /root/subject.yaml contains subject-related documentation
check "/root/subject.yaml contains subject specification info" \
  bash -c 'grep -qi "subject\|organization\|country\|province\|locality" /root/subject.yaml'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q6_CHECK__
cat > "$LAB_DIR/q6/cleanup.bash" <<'__CKA_Q6_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 6 - CRDs (cert-manager)
set -uo pipefail
echo "Cleaning up Question 6: CRDs (cert-manager)..."

kubectl delete deployment cert-manager -n cert-manager --ignore-not-found
kubectl delete namespace cert-manager --ignore-not-found
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml 2>/dev/null || true
rm -f /root/resources.yaml /root/subject.yaml

echo "[OK] Question 6 cleanup complete"
__CKA_Q6_CLEANUP__
cat > "$LAB_DIR/q6/solution.bash" <<'__CKA_Q6_SOLUTION__'
# List cert-manager CRDs and save
kubectl get crd | grep cert-manager | tee /root/resources.yaml

# Save spec subject explain output
kubectl explain certificate.spec.subject | tee /root/subject.yaml
__CKA_Q6_SOLUTION__
mkdir -p "$LAB_DIR/q7"
cat > "$LAB_DIR/q7/setup.bash" <<'__CKA_Q7_SETUP__'
#!/bin/bash
set -e

echo "Creating namespace: priority"
kubectl create namespace priority --dry-run=client -o yaml | kubectl apply -f -

echo "Creating user-defined PriorityClass: user-critical"
cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: user-critical
value: 1000
globalDefault: false
description: "Highest user-defined priority class"
EOF

echo "Creating deployment: busybox-logger in 'priority' namespace"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-logger
  namespace: priority
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox-logger
  template:
    metadata:
      labels:
        app: busybox-logger
    spec:
      containers:
      - name: busybox
        image: busybox
        command: ["sh", "-c", "while true; do echo 'logging...'; sleep 5; done"]
EOF

echo "[OK] Lab setup complete!"
__CKA_Q7_SETUP__
cat > "$LAB_DIR/q7/question.bash" <<'__CKA_Q7_QUESTION__'
# Question
# You're working in a kubernetes cluster with an existing deployment named busybox-logger running
# in the priority namespace.
# The cluster already has at least one user defined Priority Class

# Tasks:
# 1. Create a new Priority Class named high-priority for user workloads. The value of this class should
# be exactly one less than the highest existing user-defined priority class
# 2. Patch the existing deployment busybox-logger in the priority namespace to use the newly created
# high-priority class

# Video Link - https://youtu.be/CZzxGyF6OHc

#Documentation Reference
# Tip: Navigate the documentation manually to build familiarity with its structure
# (yaml) Reference -> Command line tool (kubectl) -> kubectl reference -> kubectle create -> kubectl create priorityClass
# https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_priorityclass/
# (patch by A-Elfiiky) Tasks -> Manage Kubernetes Objects -> Update API Objects in place using Kubectl patch
# https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/
__CKA_Q7_QUESTION__
cat > "$LAB_DIR/q7/check.bash" <<'__CKA_Q7_CHECK__'
#!/bin/bash
# Validation script for Question 7 - PriorityClass
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo " Validating Question 7: PriorityClass"
echo "============================================"

# 1. PriorityClass high-priority exists
check "PriorityClass 'high-priority' exists" \
  kubectl get priorityclass high-priority

# 2. PriorityClass value is exactly 1 less than highest existing user-defined class
check "PriorityClass value is one less than the highest existing user-defined class" \
  bash -c '
    HP_VAL=$(kubectl get priorityclass high-priority -o jsonpath="{.value}")
    # Get all non-system priority classes (value < 1000000000) except high-priority
    MAX_VAL=$(kubectl get priorityclass -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
vals = []
for item in data[\"items\"]:
    name = item[\"metadata\"][\"name\"]
    val = item[\"value\"]
    if name != \"high-priority\" and name != \"system-cluster-critical\" and name != \"system-node-critical\" and val < 1000000000:
        vals.append(val)
if vals:
    print(max(vals))
else:
    print(0)
")
    EXPECTED=$((MAX_VAL - 1))
    [[ "$HP_VAL" == "$EXPECTED" ]]
  '

# 3. PriorityClass is not globalDefault
check "PriorityClass is not globalDefault" \
  bash -c '
    GD=$(kubectl get priorityclass high-priority -o jsonpath="{.globalDefault}" 2>/dev/null)
    [[ "$GD" != "true" ]]
  '

# 4. Deployment busybox-logger exists in priority namespace
check "Deployment 'busybox-logger' exists in namespace 'priority'" \
  kubectl get deployment busybox-logger -n priority

# 5. Deployment uses high-priority PriorityClass
check "Deployment 'busybox-logger' uses priorityClassName 'high-priority'" \
  bash -c '[[ "$(kubectl get deployment busybox-logger -n priority -o jsonpath="{.spec.template.spec.priorityClassName}")" == "high-priority" ]]'

# 6. Pods are running
check "busybox-logger pods are Running" \
  bash -c 'kubectl get pods -n priority -l app=busybox-logger --no-headers 2>/dev/null | grep -q Running || kubectl get pods -n priority --no-headers 2>/dev/null | grep busybox | grep -q Running'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q7_CHECK__
cat > "$LAB_DIR/q7/cleanup.bash" <<'__CKA_Q7_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 7 - PriorityClass
set -uo pipefail
echo "Cleaning up Question 7: PriorityClass..."

kubectl delete deployment busybox-logger -n priority --ignore-not-found
kubectl delete namespace priority --ignore-not-found
kubectl delete priorityclass high-priority --ignore-not-found

echo "[OK] Question 7 cleanup complete"
__CKA_Q7_CLEANUP__
cat > "$LAB_DIR/q7/solution.bash" <<'__CKA_Q7_SOLUTION__'
# Create PriorityClass just below existing max (e.g., 999)
kubectl create priorityclass high-priority --value=999 --description="high priority"
kubectl get pc

# Patch deployment to use it
kubectl patch deployment busybox-logger -n priority -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
kubectl describe deployment busybox-logger -n priority | grep -i "Priority Class"
__CKA_Q7_SOLUTION__
mkdir -p "$LAB_DIR/q8"
cat > "$LAB_DIR/q8/setup.bash" <<'__CKA_Q8_SETUP__'
#!/bin/bash
# Remove the preinstalled Cilium CNI so Calico can be installed cleanly
kubectl delete daemonset cilium -n kube-system --ignore-not-found 2>/dev/null || true
kubectl delete daemonset cilium-envoy -n kube-system --ignore-not-found 2>/dev/null || true
kubectl delete serviceaccount cilium -n kube-system --ignore-not-found 2>/dev/null || true
kubectl delete clusterrole cilium --ignore-not-found 2>/dev/null || true
kubectl delete clusterrolebinding cilium --ignore-not-found 2>/dev/null || true
kubectl delete configmap cilium-config -n kube-system --ignore-not-found 2>/dev/null || true
kubectl delete namespace cilium --ignore-not-found 2>/dev/null || true

# Remove stale Cilium CNI config files from the nodes
sudo rm -f /etc/cni/net.d/*cilium*
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null node01 'sudo rm -f /etc/cni/net.d/*cilium*'

echo "# Remove stale Cilium and Calico VXLAN interfaces from the nodes"
sudo ip link delete vxlan.calico 2>/dev/null || true
sudo ip link delete cilium_vxlan 2>/dev/null || true
sudo ip link delete cilium_host 2>/dev/null || true
sudo ip link delete cilium_net 2>/dev/null || true
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null node01 'sudo ip link delete vxlan.calico 2>/dev/null || true; sudo ip link delete cilium_vxlan 2>/dev/null || true; sudo ip link delete cilium_host 2>/dev/null || true; sudo ip link delete cilium_net 2>/dev/null || true'

kubectl rollout restart deployment coredns -n kube-system

echo "# Follow the Tigera Calico documentation for the operator and custom resources manifests"
__CKA_Q8_SETUP__
cat > "$LAB_DIR/q8/question.bash" <<'__CKA_Q8_QUESTION__'
# Question
# Install and configure a CNI of your choice tht meets the specified requirements,
# Choose one of the following:

# Flannel (v0.26.1) using the manifest kube-flannel.yml
# (https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml)

# or

# Calico (v3.28.2) using the manifest tigera-operator.yaml
# (https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml)

# The CNI you choose must
# 1. Let pods communicate with each other
# 2. Support network policy enforcement
# 3. Install from manifest

#Video Link - https://youtu.be/Uc04Ui4x3EM
__CKA_Q8_QUESTION__
cat > "$LAB_DIR/q8/check.bash" <<'__CKA_Q8_CHECK__'
#!/bin/bash
# Validation script for Question 8 - CNI & Network Policy
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo " Validating Question 8: CNI & Network Policy"
echo "============================================"

# 1. A CNI is installed (check for calico pods)
check "CNI plugin is installed (calico pods running)" \
  bash -c '
    kubectl get pods -A --no-headers 2>/dev/null | grep -qiE "calico|tigera"
  '

# 2. All nodes are Ready (CNI is working)
check "All nodes are in Ready state" \
  bash -c '
    NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l)
    [[ "$NOT_READY" -eq 0 ]]
  '

# 3. Pods can communicate (kube-dns is working as a proxy check)
check "CoreDNS pods are Running (pod networking functional)" \
  bash -c '
    kubectl get pods -n kube-system --no-headers 2>/dev/null | grep coredns | grep -q Running
  '

# 4. CNI supports NetworkPolicy (Calico/Tigera detected)
check "CNI supports NetworkPolicy (Calico/Tigera detected)" \
  bash -c '
    # Calico supports NetworkPolicy; Flannel does not natively
    kubectl get pods -A --no-headers 2>/dev/null | grep -qiE "calico|tigera"
  '

# 5. CNI was installed from manifest (tigera-operator or calico namespace exists)
check "CNI installed from manifest (tigera-operator or calico namespace)" \
  bash -c '
    kubectl get ns --no-headers 2>/dev/null | grep -qiE "tigera|calico"
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q8_CHECK__
cat > "$LAB_DIR/q8/cleanup.bash" <<'__CKA_Q8_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 8 - CNI & Network Policy
set -uo pipefail
echo "Cleaning up Question 8: CNI & Network Policy..."

# Remove Calico/tigera-operator if installed
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml 2>/dev/null || true
kubectl delete namespace tigera-operator --ignore-not-found
kubectl delete namespace calico-system --ignore-not-found

# Remove Flannel if installed
kubectl delete namespace kube-flannel --ignore-not-found

echo "[OK] Question 8 cleanup complete"
echo "NOTE: CNI removal may require a node restart to fully take effect."
__CKA_Q8_CLEANUP__
cat > "$LAB_DIR/q8/solution.bash" <<'__CKA_Q8_SOLUTION__'
# Follow the Tigera Calico documentation to install the operator and custom resources
# See the Calico docs for the custom-resources.yaml file. https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart
# The custom-resources.yaml file is also here:
# https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml

# Get the cluster CIDR from kubeadm (replace with the value from your cluster)
kubectl -n kube-system get cm kubeadm-config -o yaml | grep -n "podSubnet"

# Apply Calico custom resources with the same CIDR as the cluster
# or Download the custom-resources.yaml file and edit the CIDR before applying
wget https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml
vim custom-resources.yaml
# Change the CIDR in the ipPools section to match your cluster CIDR from above command, then apply
kubectl apply -f custom-resources.yaml


kubectl get tigerastatus
kubectl get pods -n calico-system

# Check that all pods are starting, especially CoreDNS
kubectl get pods -A
kubectl get pods -n kube-system | grep coredns
__CKA_Q8_SOLUTION__
mkdir -p "$LAB_DIR/q9"
cat > "$LAB_DIR/q9/setup.bash" <<'__CKA_Q9_SETUP__'
#!/bin/bash
set -e

# Download CRI Dockerd Debian package to /root, matching typical exam setup
wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.20/cri-dockerd_0.3.20.3-0.debian-bullseye_amd64.deb -O /root/cri-dockerd.deb

echo "CRI Dockerd package downloaded to /root/cri-dockerd.deb"
__CKA_Q9_SETUP__
cat > "$LAB_DIR/q9/question.bash" <<'__CKA_Q9_QUESTION__'
# Question: Cri-Dockerd

# Task:
# Set up cri-dockerd
# Install the debian package ~/cri-dockerd.deb using dpkg
# Enable and start the cri-docker service
# Configure these parameters:
# 1. Set net.bridge.bridge-nf-call-iptables to 1
# 2. Set net.ipv6.conf.all.forwarding to 1
# 3. Set net.ipv4.ip_forward to 1
# 4. Set net.netfilter.nf_conntrack_max to 131072

# Video Link - https://youtu.be/ybzo1vXiqjU
__CKA_Q9_QUESTION__
cat > "$LAB_DIR/q9/check.bash" <<'__CKA_Q9_CHECK__'
#!/bin/bash
# Validation script for Question 9 - Cri-Dockerd
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 9: Cri-Dockerd"
echo "======================================"

# 1. cri-dockerd package is installed
check "cri-dockerd package is installed" \
  bash -c 'dpkg -l cri-dockerd 2>/dev/null | grep -q "^ii"'

# 2. cri-docker service is enabled
check "cri-docker service is enabled" \
  bash -c 'systemctl is-enabled --quiet cri-docker.service'

# 3. cri-docker service is active/running
check "cri-docker service is active (running)" \
  bash -c 'systemctl is-active --quiet cri-docker.service'

# 4. net.bridge.bridge-nf-call-iptables = 1
check "sysctl net.bridge.bridge-nf-call-iptables = 1" \
  bash -c '[[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null)" == "1" ]]'

# 5. net.ipv6.conf.all.forwarding = 1
check "sysctl net.ipv6.conf.all.forwarding = 1" \
  bash -c '[[ "$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)" == "1" ]]'

# 6. net.ipv4.ip_forward = 1
check "sysctl net.ipv4.ip_forward = 1" \
  bash -c '[[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]]'

# 7. net.netfilter.nf_conntrack_max = 131072
check "sysctl net.netfilter.nf_conntrack_max = 131072" \
  bash -c '[[ "$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)" == "131072" ]]'

# 8. Settings are persistent (exist in sysctl config)
check "Sysctl settings are persisted in /etc/sysctl.d/" \
  bash -c 'grep -rq "net.bridge.bridge-nf-call-iptables" /etc/sysctl.d/ 2>/dev/null || grep -q "net.bridge.bridge-nf-call-iptables" /etc/sysctl.conf 2>/dev/null'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q9_CHECK__
cat > "$LAB_DIR/q9/cleanup.bash" <<'__CKA_Q9_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 9 - Cri-Dockerd
set -uo pipefail
echo "Cleaning up Question 9: cri-dockerd..."

sudo systemctl disable --now cri-docker.service 2>/dev/null || true
sudo dpkg -r cri-dockerd 2>/dev/null || true
sudo rm -f /etc/sysctl.d/kube.conf
sudo sysctl --system >/dev/null 2>&1 || true

echo "[OK] Question 9 cleanup complete"
__CKA_Q9_CLEANUP__
cat > "$LAB_DIR/q9/solution.bash" <<'__CKA_Q9_SOLUTION__'
# Install and run cri-dockerd
sudo dpkg -i cri-dockerd.deb
sudo systemctl enable --now cri-docker.service
sudo systemctl status cri-docker.service

# Set sysctl (make persistent)
sudo tee /etc/sysctl.d/kube.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables=1
net.ipv6.conf.all.forwarding=1
net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_max=131072
EOF
sudo sysctl --system
__CKA_Q9_SOLUTION__
mkdir -p "$LAB_DIR/q10"
cat > "$LAB_DIR/q10/setup.bash" <<'__CKA_Q10_SETUP__'
#!/bin/bash
echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"
__CKA_Q10_SETUP__
cat > "$LAB_DIR/q10/question.bash" <<'__CKA_Q10_QUESTION__'
# Question: Taints & Tolerances

# Tasks:
# 1. Add a taint to node01 so tht no normal pods can be scheduled in this node. key=PERMISSION, value=granted, Type=NoSchedule
# 2. Schedule a Pod named nginx (image nginx) on node01 adding the correct toleration to the spec so it can be deployed

# Video Link - https://youtu.be/oy6Mdqt1-jk

#Documentation Reference
# Tip: Navigate the documentation manually to build familiarity with its structure
# Concepts -> Scheduling, Preemption and Eviction -> Taints and Tolerations
# https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
__CKA_Q10_QUESTION__
cat > "$LAB_DIR/q10/check.bash" <<'__CKA_Q10_CHECK__'
#!/bin/bash
# Validation script for Question 10 - Taints & Tolerations
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================="
echo " Validating Question 10: Taints & Tolerations"
echo "============================================="

# 1. node01 has the taint PERMISSION=granted:NoSchedule
check "node01 has taint PERMISSION=granted:NoSchedule" \
  bash -c '
    kubectl describe node node01 2>/dev/null | grep -q "PERMISSION=granted:NoSchedule"
  '

# 1b. Pod nginx exists (image nginx)
check "Pod 'nginx' exists with image nginx" \
  bash -c '[[ "$(kubectl get pod nginx -o jsonpath="{.spec.containers[0].image}" 2>/dev/null)" == nginx* ]]'

# 2. A pod exists that tolerates the taint and is scheduled on node01
check "A pod with toleration for PERMISSION=granted:NoSchedule exists" \
  bash -c '
    # Check all pods for the toleration
    kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data[\"items\"]:
    ns = pod[\"metadata\"][\"namespace\"]
    if ns.startswith(\"kube-\"):
        continue
    tolerations = pod[\"spec\"].get(\"tolerations\", [])
    for t in tolerations:
        if t.get(\"key\") == \"PERMISSION\" and t.get(\"value\") == \"granted\" and t.get(\"effect\") == \"NoSchedule\":
            sys.exit(0)
sys.exit(1)
"'

# 3. The tolerating pod is Running
check "Tolerating pod is in Running state" \
  bash -c '
    kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data[\"items\"]:
    ns = pod[\"metadata\"][\"namespace\"]
    if ns.startswith(\"kube-\"):
        continue
    tolerations = pod[\"spec\"].get(\"tolerations\", [])
    for t in tolerations:
        if t.get(\"key\") == \"PERMISSION\" and t.get(\"value\") == \"granted\" and t.get(\"effect\") == \"NoSchedule\":
            if pod[\"status\"][\"phase\"] == \"Running\":
                sys.exit(0)
sys.exit(1)
"'

# 4. The tolerating pod is on node01
check "Tolerating pod is scheduled on node01" \
  bash -c '
    kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data[\"items\"]:
    ns = pod[\"metadata\"][\"namespace\"]
    if ns.startswith(\"kube-\"):
        continue
    tolerations = pod[\"spec\"].get(\"tolerations\", [])
    for t in tolerations:
        if t.get(\"key\") == \"PERMISSION\" and t.get(\"value\") == \"granted\" and t.get(\"effect\") == \"NoSchedule\":
            node = pod[\"spec\"].get(\"nodeName\", \"\")
            if \"node01\" in node:
                sys.exit(0)
sys.exit(1)
"'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q10_CHECK__
cat > "$LAB_DIR/q10/cleanup.bash" <<'__CKA_Q10_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 10 - Taints & Tolerations
set -uo pipefail
echo "Cleaning up Question 10: Taints & Tolerations..."

# Remove taint from node01
kubectl taint nodes node01 PERMISSION=granted:NoSchedule- 2>/dev/null || true

# Delete pods created for this question
kubectl delete pod nginx nginx-fail --ignore-not-found

echo "[OK] Question 10 cleanup complete"
__CKA_Q10_CLEANUP__
cat > "$LAB_DIR/q10/solution.bash" <<'__CKA_Q10_SOLUTION__'
# Taint node01
kubectl taint nodes node01 PERMISSION=granted:NoSchedule

# Pod that tolerates the taint
cat <<'EOF' > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
  tolerations:
  - key: PERMISSION
    operator: Equal
    value: granted
    effect: NoSchedule
EOF
kubectl apply -f pod.yaml
kubectl get pods

# Negative test (optional) - should stay Pending
cat <<'EOF' > podfailure.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-fail
spec:
  containers:
  - name: nginx
    image: nginx
EOF
kubectl apply -f podfailure.yaml
kubectl describe pod nginx-fail
__CKA_Q10_SOLUTION__
mkdir -p "$LAB_DIR/q11"
cat > "$LAB_DIR/q11/setup.bash" <<'__CKA_Q11_SETUP__'
#!/bin/bash
set -e

echo "Setting up Kubernetes Gateway API migration lab..."

# 1. Install Gateway API CRDs (official source)
echo "Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml >/dev/null

# 2. Deploy a simple nginx web app
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx
        ports:
        - containerPort: 80
EOF

# 3. Create a service for the web app
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  selector:
    app: web
  ports:
  - name: http
    port: 80
    targetPort: 80
EOF

# 4. Create a self-signed TLS certificate and secret
echo "Creating TLS certificate..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=gateway.web.k8s.local/O=web" >/dev/null 2>&1

kubectl create secret tls web-tls --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f - >/dev/null
rm -f tls.crt tls.key

# 5. Create an existing Ingress resource (to migrate from)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
  - hosts:
    - gateway.web.k8s.local
    secretName: web-tls
  rules:
  - host: gateway.web.k8s.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
EOF

# 6. Create a working GatewayClass (using a mock nginx controller)
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx-class
spec:
  controllerName: example.net/nginx-gateway-controller
EOF

echo
echo "[OK] Gateway API lab setup complete!"
echo
echo "Resources created:"
echo "  - Deployment: web-deployment"
echo "  - Service: web-service"
echo "  - Ingress: web"
echo "  - GatewayClass: nginx-class"
echo
echo "Next steps:"
echo "  1.  Create a Gateway named web-gateway using hostname gateway.web.k8s.local and nginx-class."
echo "  2.  Create a HTTPRoute named web-route referencing web-service."
echo "  3.  Use 'kubectl get gatewayclass,gateway,httproute -A' to verify."
__CKA_Q11_SETUP__
cat > "$LAB_DIR/q11/question.bash" <<'__CKA_Q11_QUESTION__'
# Question
# You have an existing web application deployed in a Kubernetes cluster using an Ingress resource named web.
# You must migrate the existing Ingress configuration to the new Kubernetes Gateway API, maintaining the
# existing HTTPS access configuration

# Tasks
# 1. Create a Gateway Resource named web-gateway with hostname gateway.web.k8s.local that maintains the
# exisiting TLS and listener configuration from the existing Ingress resource named web
# 2. Create a HTTPRoute resource named web-route with hostname gateway.web.k8s.local that maintains the
# existing routing rules from the current Ingress resource named web.
# Note: A GatewayClass named nginx-class is already installed in the cluster

#Video link - https://youtu.be/G9zispvOCHE
__CKA_Q11_QUESTION__
cat > "$LAB_DIR/q11/check.bash" <<'__CKA_Q11_CHECK__'
#!/bin/bash
# Validation script for Question 11 - Gateway API
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 11: Gateway API"
echo "======================================"

# 1. Gateway named web-gateway exists
check "Gateway 'web-gateway' exists" \
  kubectl get gateway web-gateway

# 2. Gateway uses gatewayClassName nginx-class
check "Gateway uses gatewayClassName 'nginx-class'" \
  bash -c '[[ "$(kubectl get gateway web-gateway -o jsonpath="{.spec.gatewayClassName}")" == "nginx-class" ]]'

# 3. Gateway listener uses HTTPS protocol on port 443
check "Gateway listener uses HTTPS on port 443" \
  bash -c '
    PROTO=$(kubectl get gateway web-gateway -o jsonpath="{.spec.listeners[0].protocol}" 2>/dev/null)
    PORT=$(kubectl get gateway web-gateway -o jsonpath="{.spec.listeners[0].port}" 2>/dev/null)
    [[ "$PROTO" == "HTTPS" && "$PORT" == "443" ]]
  '

# 4. Gateway hostname is gateway.web.k8s.local
check "Gateway hostname is 'gateway.web.k8s.local'" \
  bash -c '
    HOST=$(kubectl get gateway web-gateway -o jsonpath="{.spec.listeners[0].hostname}" 2>/dev/null)
    [[ "$HOST" == "gateway.web.k8s.local" ]]
  '

# 5. Gateway references TLS secret (web-tls)
check "Gateway references TLS secret 'web-tls'" \
  bash -c '
    SECRET=$(kubectl get gateway web-gateway -o jsonpath="{.spec.listeners[0].tls.certificateRefs[0].name}" 2>/dev/null)
    [[ "$SECRET" == "web-tls" ]]
  '

# 6. HTTPRoute named web-route exists
check "HTTPRoute 'web-route' exists" \
  kubectl get httproute web-route

# 7. HTTPRoute references parentRef web-gateway
check "HTTPRoute references parentRef 'web-gateway'" \
  bash -c '
    PARENT=$(kubectl get httproute web-route -o jsonpath="{.spec.parentRefs[0].name}" 2>/dev/null)
    [[ "$PARENT" == "web-gateway" ]]
  '

# 8. HTTPRoute hostname is gateway.web.k8s.local
check "HTTPRoute hostname is 'gateway.web.k8s.local'" \
  bash -c '
    HOST=$(kubectl get httproute web-route -o jsonpath="{.spec.hostnames[0]}" 2>/dev/null)
    [[ "$HOST" == "gateway.web.k8s.local" ]]
  '

# 9. HTTPRoute has backend reference
check "HTTPRoute backendRef is web-service:80" \
  bash -c '
    BACKEND=$(kubectl get httproute web-route -o jsonpath="{.spec.rules[0].backendRefs[0].name}" 2>/dev/null)
    BPORT=$(kubectl get httproute web-route -o jsonpath="{.spec.rules[0].backendRefs[0].port}" 2>/dev/null)
    [[ "$BACKEND" == "web-service" && "$BPORT" == "80" ]]
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q11_CHECK__
cat > "$LAB_DIR/q11/cleanup.bash" <<'__CKA_Q11_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 11 - Gateway API
set -uo pipefail
echo "Cleaning up Question 11: Gateway API..."

kubectl delete httproute web-route --ignore-not-found
kubectl delete gateway web-gateway --ignore-not-found
kubectl delete gatewayclass nginx-class --ignore-not-found
kubectl delete ingress web --ignore-not-found
kubectl delete secret web-tls --ignore-not-found
kubectl delete service web-service --ignore-not-found
kubectl delete deployment web-deployment --ignore-not-found
rm -f ~/gw.yaml ~/http.yaml

echo "[OK] Question 11 cleanup complete"
echo "NOTE: Gateway API CRDs are left in place as they are cluster-wide."
__CKA_Q11_CLEANUP__
cat > "$LAB_DIR/q11/solution.bash" <<'__CKA_Q11_SOLUTION__'
# Step 1: Inspect existing assets (host, secret, backend service/port)
kubectl describe ingress web
kubectl describe secret web-tls

# Step 2: Create Gateway (mirrors Ingress host + TLS)
cat <<'EOF' > gw.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
spec:
  gatewayClassName: nginx-class
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: gateway.web.k8s.local
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: web-tls
EOF
kubectl apply -f gw.yaml
kubectl get gateway

# Step 3: Create HTTPRoute (mirrors Ingress rules)
cat <<'EOF' > http.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
spec:
  parentRefs:
  - name: web-gateway
  hostnames:
  - "gateway.web.k8s.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-service
      port: 80
EOF
kubectl apply -f http.yaml

# Step 4: Verify
kubectl describe gateway web-gateway
kubectl describe httproute web-route
__CKA_Q11_SOLUTION__
mkdir -p "$LAB_DIR/q12"
cat > "$LAB_DIR/q12/setup.bash" <<'__CKA_Q12_SETUP__'
#!/bin/bash
set -e

echo "Creating namespace: echo-sound"
kubectl create ns echo-sound || true

echo "Deploying Echo Server in namespace: echo-sound"
cat <<EOF | kubectl -n echo-sound apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
      - name: echo
        image: registry.k8s.io/echoserver:1.10
        ports:
        - containerPort: 8080
EOF

echo "[OK] Echo server deployment created successfully!"
__CKA_Q12_SETUP__
cat > "$LAB_DIR/q12/question.bash" <<'__CKA_Q12_QUESTION__'
# Question Ingress

# Task
# 1. Expose the existing deployment with a service called echo-service
# using Service Port 8080 type=NodePort
# 2. Create a new ingress resource named echo in the echo-sound namespace for http://example.org/echo
# 3. The availability of the Service echo-service can be checked using the following command
curl NODEIP:NODEPORT/echo

# In the exam it may give you a command like curl -o /dev/null -s -w "%{http_code}\n" http://example.org/echo
# This requires an ingress controller, to get this to work ensure your /etc/hosts file has an entry for your NodeIP
# pointing to example.org

# Video Link - https://youtu.be/sy9zABvDedQ
__CKA_Q12_QUESTION__
cat > "$LAB_DIR/q12/check.bash" <<'__CKA_Q12_CHECK__'
#!/bin/bash
# Validation script for Question 12 - Ingress
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 12: Ingress"
echo "======================================"

# 1. Service echo-service exists in echo-sound namespace
check "Service 'echo-service' exists in namespace 'echo-sound'" \
  kubectl get svc echo-service -n echo-sound

# 2. Service type is NodePort
check "Service type is NodePort" \
  bash -c '[[ "$(kubectl get svc echo-service -n echo-sound -o jsonpath="{.spec.type}")" == "NodePort" ]]'

# 3. Service port is 8080
check "Service port is 8080" \
  bash -c '
    PORT=$(kubectl get svc echo-service -n echo-sound -o jsonpath="{.spec.ports[0].port}" 2>/dev/null)
    [[ "$PORT" == "8080" ]]
  '

# 4. Ingress named echo exists in echo-sound namespace
check "Ingress 'echo' exists in namespace 'echo-sound'" \
  kubectl get ingress echo -n echo-sound

# 5. Ingress host is example.org
check "Ingress host is 'example.org'" \
  bash -c '
    HOST=$(kubectl get ingress echo -n echo-sound -o jsonpath="{.spec.rules[0].host}" 2>/dev/null)
    [[ "$HOST" == "example.org" ]]
  '

# 6. Ingress path is /echo
check "Ingress path is '/echo'" \
  bash -c '
    PATH_VAL=$(kubectl get ingress echo -n echo-sound -o jsonpath="{.spec.rules[0].http.paths[0].path}" 2>/dev/null)
    [[ "$PATH_VAL" == "/echo" ]]
  '

# 7. Ingress backend points to echo-service on port 8080
check "Ingress backend references 'echo-service' port 8080" \
  bash -c '
    SVC=$(kubectl get ingress echo -n echo-sound -o jsonpath="{.spec.rules[0].http.paths[0].backend.service.name}" 2>/dev/null)
    PORT=$(kubectl get ingress echo -n echo-sound -o jsonpath="{.spec.rules[0].http.paths[0].backend.service.port.number}" 2>/dev/null)
    [[ "$SVC" == "echo-service" && "$PORT" == "8080" ]]
  '

# 8. Deployment endpoints are healthy
check "echo-service has endpoints (pods backing the service)" \
  bash -c '
    EP=$(kubectl get endpoints echo-service -n echo-sound -o jsonpath="{.subsets[0].addresses}" 2>/dev/null)
    [[ -n "$EP" && "$EP" != "[]" ]]
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q12_CHECK__
cat > "$LAB_DIR/q12/cleanup.bash" <<'__CKA_Q12_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 12 - Ingress
set -uo pipefail
echo "Cleaning up Question 12: Ingress..."

kubectl delete ingress echo -n echo-sound --ignore-not-found
kubectl delete service echo-service -n echo-sound --ignore-not-found
kubectl delete deployment echo -n echo-sound --ignore-not-found
kubectl delete namespace echo-sound --ignore-not-found
rm -f ~/ingress.yaml

echo "[OK] Question 12 cleanup complete"
__CKA_Q12_CLEANUP__
cat > "$LAB_DIR/q12/solution.bash" <<'__CKA_Q12_SOLUTION__'
# Expose deployment as NodePort
kubectl expose deployment echo -n echo-sound --name echo-service --type NodePort --port 8080 --target-port 8080
kubectl get svc -n echo-sound echo-service

# Create ingress
cat <<'EOF' > ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo
  namespace: echo-sound
spec:
  rules:
  - host: example.org
    http:
      paths:
      - path: /echo
        pathType: Prefix
        backend:
          service:
            name: echo-service
            port:
              number: 8080
EOF
kubectl apply -f ingress.yaml
kubectl get ingress -n echo-sound

# Optional test (NodePort): curl http://<nodeIP>:<nodePort>/echo
__CKA_Q12_SOLUTION__
mkdir -p "$LAB_DIR/q13"
cat > "$LAB_DIR/q13/setup.bash" <<'__CKA_Q13_SETUP__'
#!/bin/bash
set -e

echo "Creating namespaces..."
kubectl create namespace frontend --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying backend app..."
kubectl apply -n backend -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment
  namespace: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: nginx
        ports:
        - containerPort: 80
EOF

echo "Exposing backend as ClusterIP service..."
kubectl expose deployment backend-deployment -n backend --port=80 --target-port=80 --name=backend-service

echo "Deploying frontend app..."
kubectl apply -n frontend -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
  namespace: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: curlimages/curl
        command: ["sleep", "3600"]
EOF

echo "Creating NetworkPolicy files..."
WORKDIR="${WORKDIR:-$HOME/network-policies}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

cat <<EOF > network-policy-1.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-x
  namespace: backend
spec:
  podSelector: {}
  ingress:
  - {}
  policyTypes:
  - Ingress
EOF

cat <<EOF > network-policy-2.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-y
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
    - ipBlock:
        cidr: 172.16.0.0/16
    ports:
    - protocol: TCP
      port: 80
  policyTypes:
  - Ingress
EOF

cat <<EOF > network-policy-3.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-z
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 80
  policyTypes:
  - Ingress
EOF

cd /
echo "[OK] Lab setup complete. Three network policy files created in $WORKDIR"
__CKA_Q13_SETUP__
cat > "$LAB_DIR/q13/question.bash" <<'__CKA_Q13_QUESTION__'
# Question:
# There are two deployments, Frontend and Backend
# Frontend is in the frontend namespace, Backend is in the backend namespace

# Task
# Look at the Network Policy YAML files in ./network-policies
# Decide which of the policies provides the functionality to allow interaction between the
# frontend and the backend deployments in the least permissive way and deploy that yaml

# Video Link - https://youtu.be/rA8mXYTU0W8
__CKA_Q13_QUESTION__
cat > "$LAB_DIR/q13/check.bash" <<'__CKA_Q13_CHECK__'
#!/bin/bash
# Validation script for Question 13 - Network Policy
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo " Validating Question 13: Network Policy"
echo "============================================"

# 1. A NetworkPolicy exists in the backend namespace
check "A NetworkPolicy exists in namespace 'backend'" \
  bash -c '
    COUNT=$(kubectl get networkpolicy -n backend --no-headers 2>/dev/null | wc -l)
    [[ "$COUNT" -ge 1 ]]
  '

# 2. NetworkPolicy has ingress rules (not allow-all)
check "NetworkPolicy has specific ingress rules (not blanket allow)" \
  bash -c '
    kubectl get networkpolicy -n backend -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pol in data[\"items\"]:
    ingress = pol[\"spec\"].get(\"ingress\", [])
    if ingress:
        for rule in ingress:
            froms = rule.get(\"from\", [])
            if froms:
                sys.exit(0)
sys.exit(1)
"'

# 3. NetworkPolicy allows traffic from frontend namespace
check "NetworkPolicy allows ingress from frontend namespace" \
  bash -c '
    kubectl get networkpolicy -n backend -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pol in data[\"items\"]:
    ingress = pol[\"spec\"].get(\"ingress\", [])
    for rule in ingress:
        froms = rule.get(\"from\", [])
        for f in froms:
            nssel = f.get(\"namespaceSelector\", {})
            match_labels = nssel.get(\"matchLabels\", {})
            # Check for frontend namespace selector
            for k, v in match_labels.items():
                if \"frontend\" in v or \"frontend\" in k:
                    sys.exit(0)
            # Also check podSelector in combination
            podsel = f.get(\"podSelector\", {})
            if podsel:
                pm = podsel.get(\"matchLabels\", {})
                for k, v in pm.items():
                    if \"frontend\" in v or \"frontend\" in k:
                        sys.exit(0)
sys.exit(1)
"'

# 3b. The least-permissive policy (policy-z) is applied, and nothing more open
check "Least-permissive policy 'policy-z' is applied" \
  kubectl get networkpolicy policy-z -n backend

check "No over-permissive policy (allow-all or ipBlock) in 'backend'" \
  bash -c '
    kubectl get networkpolicy -n backend -o json 2>/dev/null | python3 -c "
import json, sys
for pol in json.load(sys.stdin)[\"items\"]:
    for rule in pol[\"spec\"].get(\"ingress\", []):
        froms = rule.get(\"from\", [])
        if not froms or any(\"ipBlock\" in f for f in froms):
            sys.exit(1)
sys.exit(0)
"'

# 4. Frontend deployment exists
check "Deployment exists in 'frontend' namespace" \
  bash -c 'kubectl get deployment -n frontend --no-headers 2>/dev/null | wc -l | grep -qv "^0$"'

# 5. Backend deployment exists
check "Deployment exists in 'backend' namespace" \
  bash -c 'kubectl get deployment -n backend --no-headers 2>/dev/null | wc -l | grep -qv "^0$"'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."

echo ""
echo "============================================"
echo " Manual Validation Command"
echo "============================================"
echo "To manually verify connectivity from frontend to backend, run:"
echo "  kubectl exec -n frontend deploy/frontend-deployment -- curl -v --connect-timeout 5 backend-service.backend.svc.cluster.local:80"

exit $FAIL
__CKA_Q13_CHECK__
cat > "$LAB_DIR/q13/cleanup.bash" <<'__CKA_Q13_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 13 - Network Policy
set -uo pipefail
echo "Cleaning up Question 13: Network Policy..."

kubectl delete networkpolicy --all -n backend --ignore-not-found
kubectl delete namespace frontend --ignore-not-found
kubectl delete namespace backend --ignore-not-found
WORKDIR="${WORKDIR:-$HOME/network-policies}"
rm -rf "$WORKDIR"

echo "[OK] Question 13 cleanup complete"
__CKA_Q13_CLEANUP__
cat > "$LAB_DIR/q13/solution.bash" <<'__CKA_Q13_SOLUTION__'
# Compare provided policies and pick the least permissive that matches requirements
WORKDIR="${WORKDIR:-$HOME/network-policies}"
cat "$WORKDIR/network-policy-1.yaml"   # allows all ingress (too open)
cat "$WORKDIR/network-policy-2.yaml"   # extra IP allowed (too open)
cat "$WORKDIR/network-policy-3.yaml"   # only frontend namespace/pods allowed
kubectl get pods -n frontend --show-labels         # confirm app=frontend label
kubectl apply -f "$WORKDIR/network-policy-3.yaml"

# Validate connectivity from frontend to backend
# Replace the pod name below with the actual frontend pod name from: kubectl get pods -n frontend
kubectl exec -n frontend deploy/frontend-deployment -- curl -v --connect-timeout 5 backend-service.backend.svc.cluster.local:80
__CKA_Q13_SOLUTION__
mkdir -p "$LAB_DIR/q14"
cat > "$LAB_DIR/q14/setup.bash" <<'__CKA_Q14_SETUP__'
#!/bin/bash
echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"
__CKA_Q14_SETUP__
cat > "$LAB_DIR/q14/question.bash" <<'__CKA_Q14_QUESTION__'
# Question Storage Class

# Tasks
# 1. Create a new StorageClass named local-storage with the provisioner rancher.io/local-path. Set
# the VolumeBindingMode to WaitForFirstConsumer. Do not make the SC default
# 2. Patch the StorageClass to make it the default StorageClass
# 3. Ensure local-storage is the only default class
# Do not modify any existing Deployments or PersistentVolumeClaims

# Video link - https://youtu.be/di7X7OHn2fc
__CKA_Q14_QUESTION__
cat > "$LAB_DIR/q14/check.bash" <<'__CKA_Q14_CHECK__'
#!/bin/bash
# Validation script for Question 14 - Storage Class
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo " Validating Question 14: Storage Class"
echo "============================================"

# 1. StorageClass local-storage exists
check "StorageClass 'local-storage' exists" \
  kubectl get storageclass local-storage

# 2. Provisioner is rancher.io/local-path
check "StorageClass provisioner is 'rancher.io/local-path'" \
  bash -c '[[ "$(kubectl get storageclass local-storage -o jsonpath="{.provisioner}")" == "rancher.io/local-path" ]]'

# 3. VolumeBindingMode is WaitForFirstConsumer
check "VolumeBindingMode is 'WaitForFirstConsumer'" \
  bash -c '[[ "$(kubectl get storageclass local-storage -o jsonpath="{.volumeBindingMode}")" == "WaitForFirstConsumer" ]]'

# 4. local-storage is the default StorageClass
check "StorageClass 'local-storage' is the default" \
  bash -c '
    IS_DEFAULT=$(kubectl get storageclass local-storage -o jsonpath="{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}" 2>/dev/null)
    [[ "$IS_DEFAULT" == "true" ]]
  '

# 5. Only one default StorageClass exists (local-storage)
check "Only one default StorageClass exists" \
  bash -c '
    DEFAULT_COUNT=$(kubectl get storageclass -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for sc in data[\"items\"]:
    annotations = sc[\"metadata\"].get(\"annotations\", {})
    if annotations.get(\"storageclass.kubernetes.io/is-default-class\") == \"true\":
        count += 1
print(count)
")
    [[ "$DEFAULT_COUNT" == "1" ]]
  '

# 6. No other StorageClass is marked as default
check "No other StorageClass is marked default" \
  bash -c '
    kubectl get storageclass -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for sc in data[\"items\"]:
    name = sc[\"metadata\"][\"name\"]
    if name == \"local-storage\":
        continue
    annotations = sc[\"metadata\"].get(\"annotations\", {})
    if annotations.get(\"storageclass.kubernetes.io/is-default-class\") == \"true\":
        sys.exit(1)
sys.exit(0)
"'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q14_CHECK__
cat > "$LAB_DIR/q14/cleanup.bash" <<'__CKA_Q14_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 14 - Storage Class
set -uo pipefail
echo "Cleaning up Question 14: Storage Class..."

# Remove default annotation from local-storage before deleting
kubectl patch storageclass local-storage \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
kubectl delete storageclass local-storage --ignore-not-found
# Give the original local-path class its default back (other labs, e.g. Q1, need a default)
if kubectl get storageclass local-path >/dev/null 2>&1; then
  kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
fi
rm -f ~/sc.yaml

echo "[OK] Question 14 cleanup complete"
__CKA_Q14_CLEANUP__
cat > "$LAB_DIR/q14/solution.bash" <<'__CKA_Q14_SOLUTION__'
# Create StorageClass
cat <<'EOF' > sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
EOF
kubectl apply -f sc.yaml
kubectl get sc

# Make it default, remove default from local-path
kubectl patch storageclass local-storage -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl get sc
__CKA_Q14_SOLUTION__
mkdir -p "$LAB_DIR/q15"
cat > "$LAB_DIR/q15/setup.bash" <<'__CKA_Q15_SETUP__'
#!/bin/bash
set -e

# Step 1: Backup current kube-apiserver manifest
# (only if no backup yet - a second run must not back up the already broken file)
if [ ! -f /root/kube-apiserver.yaml.bak ]; then
  sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
fi

# Step 2: Simulate migration issue - change etcd client port to peer port 2380
sudo sed -i 's/:2379/:2380/g' /etc/kubernetes/manifests/kube-apiserver.yaml

# Step 3: Show kube-apiserver pod status/logs
echo "Checking kube-apiserver container..."
KAPISERVER_ID=$(sudo crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -n 1)
if [ -n "$KAPISERVER_ID" ]; then
    sudo crictl logs "$KAPISERVER_ID" | tail -n 10 || true
else
    echo "kube-apiserver pod not found yet"
fi

# Step 4: Verify that kubectl fails as API server is down
kubectl get nodes || echo "As expected, API server is down due to misconfigured etcd client port."
__CKA_Q15_SETUP__
cat > "$LAB_DIR/q15/question.bash" <<'__CKA_Q15_QUESTION__'
# Question:
# After a cluster migration, the controlplane kube-apiserver is not coming up
# Before the migration, the etcd was external and in HA, after migration the kube-api server was pointing to etcd peer port 2380

# Task
# Fix it

# Video Link - https://youtu.be/IL448T6r8H4
__CKA_Q15_QUESTION__
cat > "$LAB_DIR/q15/check.bash" <<'__CKA_Q15_CHECK__'
#!/bin/bash
# Validation script for Question 15 - Etcd Fix
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 15: Etcd Fix"
echo "======================================"

# 1. kube-apiserver pod is running
check "kube-apiserver pod is Running" \
  bash -c 'kubectl get pods -n kube-system --no-headers 2>/dev/null | grep kube-apiserver | grep -q Running'

# 2. etcd endpoint uses port 2379 (not 2380)
check "kube-apiserver --etcd-servers uses port 2379" \
  bash -c '
    ETCD_SERVERS=$(grep -oP "(?<=--etcd-servers=)\S+" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || \
                   kubectl get pod -n kube-system -l component=kube-apiserver -o jsonpath="{.items[0].spec.containers[0].command}" 2>/dev/null | grep -oP "(?<=--etcd-servers=)\S+")
    echo "$ETCD_SERVERS" | grep -q ":2379"
  '

# 3. etcd endpoint does NOT use port 2380
check "kube-apiserver --etcd-servers does NOT use port 2380" \
  bash -c '
    ETCD_SERVERS=$(grep -oP "(?<=--etcd-servers=)\S+" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || echo "")
    ! echo "$ETCD_SERVERS" | grep -q ":2380"
  '

# 4. kubectl can communicate with the cluster
check "kubectl can communicate with cluster (get nodes works)" \
  kubectl get nodes

# 5. etcd pod is running
check "etcd pod is Running" \
  bash -c 'kubectl get pods -n kube-system --no-headers 2>/dev/null | grep etcd | grep -q Running'

# 6. kube-scheduler is running
check "kube-scheduler pod is Running" \
  bash -c 'kubectl get pods -n kube-system --no-headers 2>/dev/null | grep kube-scheduler | grep -q Running'

# 7. All control plane components healthy
check "All control plane pods are Running" \
  bash -c '
    FAILED=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -E "kube-apiserver|kube-scheduler|kube-controller-manager|etcd" | grep -v Running | wc -l)
    [[ "$FAILED" -eq 0 ]]
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q15_CHECK__
cat > "$LAB_DIR/q15/cleanup.bash" <<'__CKA_Q15_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 15 - Etcd Fix
set -uo pipefail
echo "Cleaning up Question 15: Etcd Fix..."

# Re-introduce the broken etcd port to reset the lab for re-practice
# (only do this if you want to re-run the lab from scratch)
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
if grep -q -- '--etcd-servers=.*:2380' "$MANIFEST" 2>/dev/null; then
  echo "kube-apiserver still points to :2380 - restoring the working manifest"
  if [ -f /root/kube-apiserver.yaml.bak ]; then
    sudo cp /root/kube-apiserver.yaml.bak "$MANIFEST"
  else
    sudo sed -i 's/:2380/:2379/g' "$MANIFEST"
  fi
  echo "Waiting for the API server to come back..."
  for i in $(seq 1 60); do kubectl get nodes >/dev/null 2>&1 && break; sleep 5; done
fi
sudo rm -f /root/kube-apiserver.yaml.bak

echo "[OK] Question 15 cleanup complete"
__CKA_Q15_CLEANUP__
cat > "$LAB_DIR/q15/solution.bash" <<'__CKA_Q15_SOLUTION__'
# Check apiserver logs, fix etcd endpoint
# kube-apiserver is a static pod, not a systemd service -> use crictl / pod log files
sudo crictl ps -a | grep kube-apiserver
sudo crictl logs $(sudo crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail
sudo ls /var/log/pods/ | grep apiserver
sudo journalctl -u kubelet | tail -20      # kubelet shows why the static pod fails
sudo sed -n '1,200p' /etc/kubernetes/manifests/kube-apiserver.yaml
# Ensure flag uses correct etcd port
# --etcd-servers=https://127.0.0.1:2379
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml   # correct port/IP, save and wait for static pod restart

# If scheduler also broken, verify its flags
kubectl -n kube-system get pods | grep kube-scheduler
sudo vi /etc/kubernetes/manifests/kube-scheduler.yaml   # kubeconfig path, API server endpoint, cert refs
__CKA_Q15_SOLUTION__
mkdir -p "$LAB_DIR/q16"
cat > "$LAB_DIR/q16/setup.bash" <<'__CKA_Q16_SETUP__'
#!/bin/bash
set -e

# Step 1: Create namespace
kubectl create namespace relative || true

# Step 2: Create deployment
kubectl -n relative create deployment nodeport-deployment \
  --image=nginx --replicas=2 --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Expose deployment via NodePort
echo "Deployment 'nodeport-deployment' created in namespace 'relative'."
echo "Task: expose it via NodePort using a Service."
__CKA_Q16_SETUP__
cat > "$LAB_DIR/q16/question.bash" <<'__CKA_Q16_QUESTION__'
# Question
# There is a deployment named nodeport-deployment in the relative namespace

# Tasks:
# 1. Configure the deployment so it can be exposed on port 80, name=http, protocol TCP
# 2. Create a new Service named nodeport-service exposing the container port 80, protocol TCP, Node Port 30080
# 3. Configure the new Service to also expose the individual pods using NodePort

# Video Link
__CKA_Q16_QUESTION__
cat > "$LAB_DIR/q16/check.bash" <<'__CKA_Q16_CHECK__'
#!/bin/bash
# Validation script for Question 16 - NodePort
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 16: NodePort"
echo "======================================"

# Detect the namespace (question says "relative namespace")
NS="relative"

# 1. Deployment nodeport-deployment exists
check "Deployment 'nodeport-deployment' exists in namespace '$NS'" \
  kubectl get deployment nodeport-deployment -n "$NS"

# 2. Deployment has containerPort 80 defined
check "Deployment has containerPort 80 configured" \
  bash -c '
    PORTS=$(kubectl get deployment nodeport-deployment -n '"$NS"' -o jsonpath="{.spec.template.spec.containers[0].ports[*].containerPort}" 2>/dev/null)
    echo " $PORTS " | grep -q " 80 "
  '

# 3. Container port name is "http"
check "Container port name is 'http'" \
  bash -c '
    NAME=$(kubectl get deployment nodeport-deployment -n '"$NS"' -o jsonpath="{.spec.template.spec.containers[0].ports[0].name}" 2>/dev/null)
    [[ "$NAME" == "http" ]]
  '

# 4. Container port protocol is TCP
check "Container port protocol is TCP" \
  bash -c '
    PROTO=$(kubectl get deployment nodeport-deployment -n '"$NS"' -o jsonpath="{.spec.template.spec.containers[0].ports[0].protocol}" 2>/dev/null)
    [[ "$PROTO" == "TCP" ]]
  '

# 5. Service nodeport-service exists
check "Service 'nodeport-service' exists in namespace '$NS'" \
  kubectl get svc nodeport-service -n "$NS"

# 6. Service type is NodePort
check "Service type is NodePort" \
  bash -c '[[ "$(kubectl get svc nodeport-service -n '"$NS"' -o jsonpath="{.spec.type}")" == "NodePort" ]]'

# 7. Service port is 80
check "Service port is 80" \
  bash -c '
    PORT=$(kubectl get svc nodeport-service -n '"$NS"' -o jsonpath="{.spec.ports[0].port}" 2>/dev/null)
    [[ "$PORT" == "80" ]]
  '

# 8. Service targetPort is 80
check "Service targetPort is 80 (or named port http)" \
  bash -c '
    TP=$(kubectl get svc nodeport-service -n '"$NS"' -o jsonpath="{.spec.ports[0].targetPort}" 2>/dev/null)
    [[ "$TP" == "80" || "$TP" == "http" ]]
  '

# 9. NodePort is 30080
check "Service nodePort is 30080" \
  bash -c '
    NP=$(kubectl get svc nodeport-service -n '"$NS"' -o jsonpath="{.spec.ports[0].nodePort}" 2>/dev/null)
    [[ "$NP" == "30080" ]]
  '

# 10. Service protocol is TCP
check "Service port protocol is TCP" \
  bash -c '
    PROTO=$(kubectl get svc nodeport-service -n '"$NS"' -o jsonpath="{.spec.ports[0].protocol}" 2>/dev/null)
    [[ "$PROTO" == "TCP" ]]
  '

# 11. Service has endpoints
check "Service has active endpoints" \
  bash -c '
    EP=$(kubectl get endpoints nodeport-service -n '"$NS"' -o jsonpath="{.subsets[0].addresses}" 2>/dev/null)
    [[ -n "$EP" && "$EP" != "[]" ]]
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q16_CHECK__
cat > "$LAB_DIR/q16/cleanup.bash" <<'__CKA_Q16_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 16 - NodePort
set -uo pipefail
echo "Cleaning up Question 16: NodePort..."

kubectl delete service nodeport-service -n relative --ignore-not-found
kubectl delete deployment nodeport-deployment -n relative --ignore-not-found
kubectl delete namespace relative --ignore-not-found
rm -f ~/svc.yaml

echo "[OK] Question 16 cleanup complete"
__CKA_Q16_CLEANUP__
cat > "$LAB_DIR/q16/solution.bash" <<'__CKA_Q16_SOLUTION__'
# Add container port to deployment
kubectl patch deployment nodeport-deployment -n relative -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "ports":[{"name":"http","containerPort":80,"protocol":"TCP"}]
  }]}}}}'
kubectl get deploy nodeport-deployment -n relative -o wide

# Create NodePort service on 30080
cat <<'EOF' > svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: nodeport-service
  namespace: relative
spec:
  type: NodePort
  selector:
    app: nodeport-deployment
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    nodePort: 30080
EOF
kubectl apply -f svc.yaml
kubectl get svc nodeport-service -n relative -o wide
# Test: curl http://<nodeIP>:30080
__CKA_Q16_SOLUTION__
mkdir -p "$LAB_DIR/q17"
cat > "$LAB_DIR/q17/setup.bash" <<'__CKA_Q17_SETUP__'
#!/bin/bash
set -e

# Step 1: Create namespace
kubectl create namespace nginx-static || true

# Step 2: Create a TLS secret (self-signed)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=ckaquestion.k8s.local" 2>/dev/null
kubectl -n nginx-static create secret tls nginx-tls --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
rm -f tls.key tls.crt

# Step 3: Create ConfigMap with TLSv1.2 and TLSv1.3 enabled
cat <<EOF | kubectl -n nginx-static apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
          return 200 "Hello TLS\n";
        }
      }
    }
EOF

# Step 4: Deploy nginx using the ConfigMap and TLS secret
cat <<EOF | kubectl -n nginx-static apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-static
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-static
  template:
    metadata:
      labels:
        app: nginx-static
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls
          mountPath: /etc/nginx/tls
      volumes:
      - name: config
        configMap:
          name: nginx-config
      - name: tls
        secret:
          secretName: nginx-tls
EOF

# Step 5: Create a ClusterIP service
kubectl -n nginx-static expose deployment nginx-static --port=443 --target-port=443 --name=nginx-static --dry-run=client -o yaml | kubectl apply -f -

echo "nginx TLS lab setup complete."

__CKA_Q17_SETUP__
cat > "$LAB_DIR/q17/question.bash" <<'__CKA_Q17_QUESTION__'
# Question:
# There is an existing deployment in the nginx-static namespace. The deployment contains a ConfigMap that supports
# TLSv1.2 and TLSv1.3 as well as a Secret for TLS.

# There is a service called nginx-static in the nginx-static namespace that is currently exposing the deployment.

# Task:
# 1. Configure the ConfigMap to only support TLSv1.3
# 2. Add the IP address of the service in /etc/hosts and name it ckaquestion.k8s.local
# 3. Verify everything is working using the following commands
    curl -vk --tls-max 1.2 https://ckaquestion.k8s.local # should fail
    curl -vk --tlsv1.3 https://ckaquestion.k8s.local # should work

# Video Link
__CKA_Q17_QUESTION__
cat > "$LAB_DIR/q17/check.bash" <<'__CKA_Q17_CHECK__'
#!/bin/bash
# Validation script for Question 17 - TLS Config
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 17: TLS Config"
echo "======================================"

NS="nginx-static"

# 1. ConfigMap nginx-config exists
check "ConfigMap 'nginx-config' exists in namespace '$NS'" \
  kubectl get configmap nginx-config -n "$NS"

# 2. ConfigMap does NOT contain TLSv1.2
check "ConfigMap does NOT reference TLSv1.2" \
  bash -c '
    CM_DATA=$(kubectl get configmap nginx-config -n '"$NS"' -o jsonpath="{.data.nginx\.conf}" 2>/dev/null)
    ! echo "$CM_DATA" | grep -q "TLSv1.2"
  '

# 3. ConfigMap contains TLSv1.3
check "ConfigMap references TLSv1.3" \
  bash -c '
    CM_DATA=$(kubectl get configmap nginx-config -n '"$NS"' -o jsonpath="{.data.nginx\.conf}" 2>/dev/null)
    echo "$CM_DATA" | grep -q "TLSv1.3"
  '

# 4. /etc/hosts has entry for ckaquestion.k8s.local
check "/etc/hosts contains entry for 'ckaquestion.k8s.local'" \
  bash -c 'grep -q "ckaquestion.k8s.local" /etc/hosts'

# 5. /etc/hosts IP matches service IP
check "/etc/hosts IP matches nginx-static ClusterIP" \
  bash -c '
    SVC_IP=$(kubectl get svc nginx-static -n '"$NS"' -o jsonpath="{.spec.clusterIP}" 2>/dev/null)
    grep "ckaquestion.k8s.local" /etc/hosts | grep -q "$SVC_IP"
  '

# 6. Deployment is running
check "nginx-static deployment is running" \
  bash -c '
    kubectl get deployment -n '"$NS"' --no-headers 2>/dev/null | grep -q "nginx"
  '

# 7. Pods are running
check "nginx-static pods are Running" \
  bash -c '
    kubectl get pods -n '"$NS"' --no-headers 2>/dev/null | grep -q Running
  '

# 8. TLS 1.2 connection fails (if curl available and service reachable)
check "TLS 1.2 connection is rejected" \
  bash -c '
    SVC_IP=$(kubectl get svc nginx-static -n '"$NS"' -o jsonpath="{.spec.clusterIP}" 2>/dev/null)
    if [[ -z "$SVC_IP" ]]; then exit 1; fi
    # curl with --tls-max 1.2 should fail (exit code != 0 or HTTP error)
    ! curl -sk --max-time 5 --tls-max 1.2 "https://$SVC_IP" >/dev/null 2>&1
  '

# 9. TLS 1.3 connection succeeds
check "TLS 1.3 connection succeeds" \
  bash -c '
    SVC_IP=$(kubectl get svc nginx-static -n '"$NS"' -o jsonpath="{.spec.clusterIP}" 2>/dev/null)
    if [[ -z "$SVC_IP" ]]; then exit 1; fi
    curl -sk --max-time 5 --tlsv1.3 "https://$SVC_IP" >/dev/null 2>&1
  '

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q17_CHECK__
cat > "$LAB_DIR/q17/cleanup.bash" <<'__CKA_Q17_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 17 - TLS Config
set -uo pipefail
echo "Cleaning up Question 17: TLS Config..."

kubectl delete deployment -n nginx-static --all --ignore-not-found
kubectl delete service nginx-static -n nginx-static --ignore-not-found
kubectl delete configmap nginx-config -n nginx-static --ignore-not-found
kubectl delete secret -n nginx-static --all --ignore-not-found
kubectl delete namespace nginx-static --ignore-not-found

# Remove /etc/hosts entry for ckaquestion.k8s.local
sudo sed -i '/ckaquestion.k8s.local/d' /etc/hosts

echo "[OK] Question 17 cleanup complete"
__CKA_Q17_CLEANUP__
cat > "$LAB_DIR/q17/solution.bash" <<'__CKA_Q17_SOLUTION__'
# Step one
# We want to edit the config map to remove all references to tls v1.2
k edit cm -n nginx-static nginx-config # remove TLSv1.2 from SSL protocols (remove from last applied configuration for safety)

# Step 2
# We need to get the IP of the service
k get svc -n nginx-static
# We need to add this IP with the host name to /etc/hosts
echo 'x.x.x.x ckaquestion.k8s.local' | sudo tee -a /etc/hosts
# Check the hosts file has been updated the IP and host should be added to the bottom of the file
sudo cat /etc/hosts

# Step 3
# If we run the check commands now we see v1.2 is still working, this is because we need to restart the deployment to use the new CM config
k rollout restart -n nginx-static deployment nginx-static
# Test the commands again and the v1.2 should no longer work
__CKA_Q17_SOLUTION__
mkdir -p "$LAB_DIR/q18"
cat > "$LAB_DIR/q18/setup.bash" <<'__CKA_Q18_SETUP__'
#!/bin/bash
set -e

# Step 1: Create namespace
kubectl create namespace patch-ns || true

# Step 2: Create deployment with constrained resource limits
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-app
  namespace: patch-ns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: resource-app
  template:
    metadata:
      labels:
        app: resource-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.19
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF

# Step 3: Install a PROMPT_COMMAND hook to capture every command to a dedicated audit log.
# This is more reliable than reading ~/.bash_history (which is flushed lazily).
AUDIT_LOG="/tmp/cka-q18-audit.log"
truncate -s 0 "$AUDIT_LOG" 2>/dev/null || true

HOOK='export CKA_Q18_AUDIT=/tmp/cka-q18-audit.log; _cka_q18_audit() { history 1 | sed "s/^[[:space:]]*[0-9]*[[:space:]]*/" >> "$CKA_Q18_AUDIT"; }; PROMPT_COMMAND="_cka_q18_audit${PROMPT_COMMAND:+; $PROMPT_COMMAND}"'

# Write the hook to a sourced file so the user can activate it
cat > /tmp/cka-q18-hook.bash <<'HOOKEOF'
export CKA_Q18_AUDIT=/tmp/cka-q18-audit.log
_cka_q18_audit() {
  history 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' >> "$CKA_Q18_AUDIT"
}
if [[ "$PROMPT_COMMAND" != *"_cka_q18_audit"* ]]; then
  PROMPT_COMMAND="_cka_q18_audit${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
HOOKEOF

echo ""
echo "Lab setup complete."
echo "Deployment 'resource-app' created in namespace 'patch-ns'."
echo ""
echo "(The checker reads metadata.managedFields, so no history hook is needed.)"
__CKA_Q18_SETUP__
cat > "$LAB_DIR/q18/question.bash" <<'__CKA_Q18_QUESTION__'
# Question 18 – kubectl patch
#
# Context:
#   A deployment named resource-app exists in the patch-ns namespace.
#   The current resource limits are too low for the expected workload:
#     CPU limit:    200m
#     Memory limit: 256Mi
#
# Task:
#   Using ONLY kubectl patch (not kubectl edit or kubectl apply):
#   1. Update the CPU limit of the nginx container to 500m
#   2. Update the Memory limit of the nginx container to 512Mi
#
# Constraints:
#   - You must use kubectl patch to make these changes
#   - Do not change the CPU or Memory requests
#   - The deployment must remain available (2 replicas)
#
# Verification:
#   Run the following command to confirm your changes are correct:
#
#     kubectl get deployment resource-app -n patch-ns \
#       -o jsonpath='{.spec.template.spec.containers[0].resources}' | python3 -m json.tool
#
#   Expected output should show:
#     "limits": { "cpu": "500m", "memory": "512Mi" }
#     "requests": { "cpu": "100m", "memory": "128Mi" }
#
__CKA_Q18_QUESTION__
cat > "$LAB_DIR/q18/check.bash" <<'__CKA_Q18_CHECK__'
#!/bin/bash
# Validation script for Question 18 - kubectl patch
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Validating Question 18: kubectl patch"
echo "======================================"

NS="patch-ns"
HISTORY_FILE="${HISTFILE:-$HOME/.bash_history}"
AUDIT_LOG="${CKA_Q18_AUDIT:-/tmp/cka-q18-audit.log}"

find_history_files() {
  local files=()

  # Prefer the dedicated audit log written by the PROMPT_COMMAND hook (most reliable)
  [[ -f "$AUDIT_LOG" ]] && files+=("$AUDIT_LOG")

  # Fall back to standard history files
  [[ -f "$HISTORY_FILE" ]] && files+=("$HISTORY_FILE")
  [[ -f "/root/.bash_history" ]] && files+=("/root/.bash_history")

  if [[ -n "${SUDO_USER:-}" && -f "/home/${SUDO_USER}/.bash_history" ]]; then
    files+=("/home/${SUDO_USER}/.bash_history")
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${files[@]}" | sort -u
}

history_contains() {
  local pattern="$1"
  local history_files

  history_files=$(find_history_files) || return 1
  grep -qiE "$pattern" $history_files
}

history_not_contains() {
  local pattern="$1"

  ! history_contains "$pattern"
}

# 1. Namespace patch-ns exists
check "Namespace 'patch-ns' exists" \
  kubectl get namespace "$NS"

# 2. Deployment resource-app exists
check "Deployment 'resource-app' exists in namespace '$NS'" \
  kubectl get deployment resource-app -n "$NS"

# 3. CPU limit updated to 500m
check "Container CPU limit is 500m" \
  bash -c '
    CPU=$(kubectl get deployment resource-app -n '"$NS"' \
      -o jsonpath="{.spec.template.spec.containers[0].resources.limits.cpu}" 2>/dev/null)
    [[ "$CPU" == "500m" ]]
  '

# 4. Memory limit updated to 512Mi
check "Container Memory limit is 512Mi" \
  bash -c '
    MEM=$(kubectl get deployment resource-app -n '"$NS"' \
      -o jsonpath="{.spec.template.spec.containers[0].resources.limits.memory}" 2>/dev/null)
    [[ "$MEM" == "512Mi" ]]
  '

# 5. CPU request unchanged (100m)
check "Container CPU request is still 100m (unchanged)" \
  bash -c '
    CPU_REQ=$(kubectl get deployment resource-app -n '"$NS"' \
      -o jsonpath="{.spec.template.spec.containers[0].resources.requests.cpu}" 2>/dev/null)
    [[ "$CPU_REQ" == "100m" ]]
  '

# 6. Memory request unchanged (128Mi)
check "Container Memory request is still 128Mi (unchanged)" \
  bash -c '
    MEM_REQ=$(kubectl get deployment resource-app -n '"$NS"' \
      -o jsonpath="{.spec.template.spec.containers[0].resources.requests.memory}" 2>/dev/null)
    [[ "$MEM_REQ" == "128Mi" ]]
  '

# 7. Replicas still 2
check "Deployment still has 2 replicas" \
  bash -c '
    REPLICAS=$(kubectl get deployment resource-app -n '"$NS"' \
      -o jsonpath="{.spec.replicas}" 2>/dev/null)
    [[ "$REPLICAS" == "2" ]]
  '

# 8. Pods are running
check "Deployment pods are Running" \
  bash -c '
    kubectl get pods -n '"$NS"' --no-headers 2>/dev/null | grep -q Running
  '

# 9. Verify patch command was used (kubectl or k)
# Note: this checks the persisted history file. The user's interactive shell must
# have already written commands to that file.
# Every write is recorded in metadata.managedFields[].manager (kubectl-patch, kubectl-edit, ...).
# This works without any shell history hook.
managers_json() { kubectl get deployment resource-app -n "$NS" -o json --show-managed-fields 2>/dev/null; }
check "limits were changed with kubectl patch (managedFields)" \
  bash -c "$(declare -f managers_json); NS=$NS"'
    managers_json | python3 -c "
import json, sys
for m in json.load(sys.stdin)[\"metadata\"].get(\"managedFields\", []):
    if m.get(\"manager\") == \"kubectl-patch\" and \"f:limits\" in json.dumps(m.get(\"fieldsV1\", {})):
        sys.exit(0)
sys.exit(1)
"'

# 10. Verify kubectl/k edit was NOT used for resource-app
check "kubectl edit / set / replace were NOT used (managedFields)" \
  bash -c "$(declare -f managers_json); NS=$NS"'
    ! managers_json | python3 -c "
import json, sys
bad = {\"kubectl-edit\", \"kubectl-set\", \"kubectl-replace\"}
ms = {m.get(\"manager\") for m in json.load(sys.stdin)[\"metadata\"].get(\"managedFields\", [])}
sys.exit(0 if ms & bad else 1)
"'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All checks passed!" || echo "Some checks failed."
exit $FAIL
__CKA_Q18_CHECK__
cat > "$LAB_DIR/q18/cleanup.bash" <<'__CKA_Q18_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 18 - kubectl patch
set -uo pipefail
echo "Cleaning up Question 18: kubectl patch..."

kubectl delete deployment resource-app -n patch-ns --ignore-not-found
kubectl delete namespace patch-ns --ignore-not-found

echo "[OK] Question 18 cleanup complete"
__CKA_Q18_CLEANUP__
cat > "$LAB_DIR/q18/solution.bash" <<'__CKA_Q18_SOLUTION__'
# Solution: kubectl patch to update resource limits
#
# Use a strategic merge patch to update only the resource limits of the nginx container.
# Strategic merge patch is smart enough to match the container by name, so it will
# only change the fields you specify and leave everything else (requests, replicas, etc.) intact.

kubectl patch deployment resource-app -n patch-ns \
  --type='strategic' \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'

# Alternatively, using a JSON merge patch (--type=merge) also works but note that
# merge patch replaces the entire "limits" object, so you must include all limit fields:
#
# kubectl patch deployment resource-app -n patch-ns \
#   --type='merge' \
#   -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'

# Verify the change was applied:
kubectl get deployment resource-app -n patch-ns \
  -o jsonpath='{.spec.template.spec.containers[0].resources}' | python3 -m json.tool

# Or check with describe:
kubectl describe deployment resource-app -n patch-ns | grep -A 5 "Limits:"

# ==============================================================================
# Alternative Approach: Using kubectl patch with a YAML file
# ==============================================================================
#
# This approach is useful when you want to prepare the patch in advance or
# make the changes more explicit.
#
# Step 1: Get the current deployment YAML
kubectl get deployment resource-app -n patch-ns -o yaml > deployment.yaml

# Step 2: Create a patch YAML file with only the fields you want to change
cat > patch.yaml <<'EOF'
spec:
  template:
    spec:
      containers:
      - name: nginx
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Step 3: Apply the strategic merge patch from the file
kubectl patch deployment resource-app -n patch-ns --patch-file=patch.yaml

# Verify the changes:
kubectl get deployment resource-app -n patch-ns -o jsonpath='{.spec.template.spec.containers[0].resources}' | python3 -m json.tool
__CKA_Q18_SOLUTION__
mkdir -p "$LAB_DIR/q19"
cat > "$LAB_DIR/q19/setup.bash" <<'__CKA_Q19_SETUP__'
#!/bin/bash
# LabSetUp.bash for Question 19 - Resource Allocation v2

set -uo pipefail

kubectl create namespace relative-fawn --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

cat <<'EOF' | kubectl apply -f - 2>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: relative-fawn
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "100Mi"
          limits:
            cpu: "300m"
            memory: "500Mi"
EOF

echo "Lab setup complete."

__CKA_Q19_SETUP__
cat > "$LAB_DIR/q19/question.bash" <<'__CKA_Q19_QUESTION__'
# Question 19: WordPress Deployment — Properly Size Resource Requests

# SCENARIO:
# A WordPress deployment in namespace 'relative-fawn' has 3 replicas.

# TASK:
# Edit the WordPress deployment so that each pod's resource requests
# equally divide the node's available resources among the 3 replicas.
# Limits do not need to be changed.

__CKA_Q19_QUESTION__
cat > "$LAB_DIR/q19/check.bash" <<'__CKA_Q19_CHECK__'
#!/bin/bash
# Validation script for Question 19 - WordPress Pod Scheduling

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

check() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "==========================================="
echo " Validating Question 19: WordPress Scheduling"
echo "==========================================="

# 1. Namespace exists
check "Namespace 'relative-fawn' exists" \
  kubectl get namespace relative-fawn

# 2. WordPress deployment exists
check "Deployment 'wordpress' exists in relative-fawn" \
  kubectl get deployment wordpress -n relative-fawn

# 3. WordPress has 3 replicas configured
check "WordPress deployment has 3 replicas" \
  bash -c '[[ "$(kubectl get deployment wordpress -n relative-fawn -o jsonpath="{.spec.replicas}")" == "3" ]]'

# 4. All 3 WordPress pods are Running
check "All 3 WordPress pods are Running" \
  bash -c '[[ $(kubectl get pods -n relative-fawn -l app=wordpress --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l) -eq 3 ]]'

# 5. No Pending pods in the namespace
check "No Pending pods in relative-fawn" \
  bash -c '[[ $(kubectl get pods -n relative-fawn --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l) -eq 0 ]]'

# 6. WordPress pods have CPU requests set
check "WordPress container has CPU requests defined" \
  bash -c '
    REQ=$(kubectl get deployment wordpress -n relative-fawn -o jsonpath="{.spec.template.spec.containers[0].resources.requests.cpu}" 2>/dev/null)
    [[ -n "$REQ" && "$REQ" != "0" ]]
  '

# 7. WordPress CPU requests were increased from 100m (properly sized)
check "WordPress CPU request was increased (greater than 100m)" \
  bash -c '
    REQ=$(kubectl get deployment wordpress -n relative-fawn -o jsonpath="{.spec.template.spec.containers[0].resources.requests.cpu}" 2>/dev/null)
    python3 -c "import sys; v=sys.argv[1]; m=float(v[:-1]) if v.endswith(\"m\") else float(v)*1000; sys.exit(0 if m>100 else 1)" "$REQ"
  '

# 8. WordPress memory requests were increased from 100Mi (properly sized)
check "WordPress memory request was increased (greater than 100Mi)" \
  bash -c '
    REQ=$(kubectl get deployment wordpress -n relative-fawn -o jsonpath="{.spec.template.spec.containers[0].resources.requests.memory}" 2>/dev/null)
    python3 -c "
import re, sys
n, u = re.fullmatch(r\"([0-9.]+)([A-Za-z]*)\", sys.argv[1]).groups()
f = {\"\": 1/2**20, \"Ki\": 1/1024, \"Mi\": 1, \"Gi\": 1024, \"K\": 1e3/2**20, \"M\": 1e6/2**20, \"G\": 1e9/2**20}[u]
sys.exit(0 if float(n)*f > 100 else 1)" "$REQ"
  '

# 9. Limits were NOT modified (memory still 500Mi)
check "WordPress memory limit unchanged (still 500Mi)" \
  bash -c '
    LIM=$(kubectl get deployment wordpress -n relative-fawn -o jsonpath="{.spec.template.spec.containers[0].resources.limits.memory}" 2>/dev/null)
    VAL=${LIM%Mi}
    [[ ${VAL:-0} -eq 500 ]]
  '

# 9b. CPU limit not modified (still 300m)
check "WordPress CPU limit unchanged (still 300m)" \
  bash -c '[[ "$(kubectl get deployment wordpress -n relative-fawn -o jsonpath="{.spec.template.spec.containers[0].resources.limits.cpu}")" == "300m" ]]'

# 10. All 3 pods have equal CPU requests (all match the deployment template)
check "All 3 pods have equal CPU requests" \
  bash -c '
    CPUS=$(kubectl get pods -n relative-fawn -l app=wordpress -o jsonpath="{.items[*].spec.containers[0].resources.requests.cpu}" 2>/dev/null)
    UNIQUE=$(echo $CPUS | tr " " "\n" | sort -u | wc -l)
    COUNT=$(echo $CPUS | tr " " "\n" | wc -l)
    [[ $COUNT -eq 3 && $UNIQUE -eq 1 ]]
  '

# 11. All 3 pods have equal memory requests
check "All 3 pods have equal memory requests" \
  bash -c '
    MEMS=$(kubectl get pods -n relative-fawn -l app=wordpress -o jsonpath="{.items[*].spec.containers[0].resources.requests.memory}" 2>/dev/null)
    UNIQUE=$(echo $MEMS | tr " " "\n" | sort -u | wc -l)
    COUNT=$(echo $MEMS | tr " " "\n" | wc -l)
    [[ $COUNT -eq 3 && $UNIQUE -eq 1 ]]
  '

echo ""
echo "==========================================="
echo " Summary"
echo "==========================================="
echo "  Passed: $PASS/$TOTAL"
echo "  Failed: $FAIL/$TOTAL"
echo "==========================================="

if [ $FAIL -eq 0 ]; then
  echo "  Result: SUCCESS"
  exit 0
else
  echo "  Result: FAILURE"
  exit 1
fi

__CKA_Q19_CHECK__
cat > "$LAB_DIR/q19/cleanup.bash" <<'__CKA_Q19_CLEANUP__'
#!/bin/bash
# Cleanup script for Question 19 - WordPress Pod Scheduling

set -uo pipefail

echo "[*] Cleaning up Question 19: WordPress Scheduling..."

# Delete the namespace (this removes all resources inside it)
kubectl delete namespace relative-fawn --ignore-not-found
echo "[OK] Namespace 'relative-fawn' deleted (includes wordpress + monitoring-agent)"

echo "[OK] Question 19 cleanup complete"

__CKA_Q19_CLEANUP__
cat > "$LAB_DIR/q19/solution.bash" <<'__CKA_Q19_SOLUTION__'
# Solution Notes for Question 19: Properly Size WordPress Resource Requests

# Step 1: Check the node's allocatable resources
echo "[*] Checking node allocatable..."
kubectl describe node | grep -A6 'Allocatable'
# Allocatable:
#   cpu:                1           (= 1000m)
#   memory:             1846528Ki   (≈ 1800Mi)

# Step 2: Check currently allocated resources
echo "[*] Checking allocated resources..."
kubectl describe node | grep -A10 'Allocated resources'
# You'll see the sum of all pod requests vs allocatable

# Step 3: List all pod requests in the namespace
echo "[*] Listing pod requests..."
kubectl get pods -n relative-fawn -o custom-columns="NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory"
# wordpress pods: 100m CPU, 100Mi memory each (too low!)

# Step 4: Calculate correct requests
#
# KEY FORMULA: (allocatable - overhead) / replicas
#
# Overhead = system pods (kube-proxy, coredns, etc.) — typically ~150m CPU / ~250Mi memory
#
# For this lab (1 CPU node):
#   CPU:    (1000m - 150m) / 3 = 850m / 3 ≈ 266m per pod  → use 250m
#   Memory: (1800Mi - 250Mi) / 3 = 1550Mi / 3 ≈ 516Mi per pod
#           BUT the deployment limit is 500Mi, so requests cannot exceed 500Mi
#           → use 300Mi (stays under the 500Mi limit)
#
# For the exam (3 CPU node):
#   CPU:    (3000m - 600m) / 3 = 2400m / 3 = 800m per pod
#   Memory: same formula with the exam node's memory
#
# NOTE: Requests must always be ≤ limits. If your calculated value exceeds
#       the existing limit, use a value just under the limit instead.
# You need to stay UNDER the total, so always round down.

# Step 5: Update WordPress requests (do NOT modify limits)
echo "[*] Patching WordPress deployment with correct requests..."
kubectl -n relative-fawn set resources deployment/wordpress \
  --containers=wordpress \
  --requests=cpu=250m,memory=300Mi

# Alternative: kubectl edit deployment wordpress -n relative-fawn
# Change only the requests section:
#   requests:
#     cpu: "250m"
#     memory: "300Mi"
# Leave limits as-is (300m CPU, 500Mi memory)

# Step 6: Wait for rollout and verify
echo "[*] Waiting for rollout..."
kubectl rollout status deployment wordpress -n relative-fawn --timeout=120s

echo "[*] Verifying all pods are running..."
kubectl get pods -n relative-fawn
# All 3 wordpress pods should be Running

echo "[*] Final resource check..."
kubectl describe node | grep -A10 'Allocated resources'
# Allocated CPU:    ~150m (system) + 3×250m (wordpress) = 900m
# Allocated Memory: ~250Mi (system) + 3×300Mi (wordpress) = 1150Mi

# EXAM TIPS:
# - The formula is key: (allocatable - overhead) / replicas
# - Only REQUESTS matter for scheduling, not limits or actual usage
# - Use kubectl describe node to find allocatable and current allocation
# - Overhead = system pods only (kube-proxy, coredns, etc.)
# - On the exam with 3 CPUs: (3000 - 600) / 3 = 800m per pod
# - On this lab with 1 CPU:  (1000 - 150) / 3 ≈ 266m → use 250m to be safe

echo "[OK] Solution complete!"

__CKA_Q19_SOLUTION__
}

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

num_ok() { [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 19 )); }

run() {  # run <action> <n>
  local f="$LAB_DIR/q$2/$1.bash"
  echo -e "\033[0;36m==> Q$2 ${TITLE[$2]} : $1\033[0m"
  case "$1" in
    question|solution) cat "$f" ;;
    *) bash "$f" ;;
  esac
}

# install this file as the command 'cka' (re-run bash cka-prep.sh after editing it)
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
if [[ "$SELF" != /usr/local/bin/cka && -w /usr/local/bin ]] && ! cmp -s "$SELF" /usr/local/bin/cka; then
  install -m 755 "$SELF" /usr/local/bin/cka && echo "Installed command: cka   (try: cka list)"
fi

ACTION="${1:-}"; N="${2:-}"
[[ -z "$ACTION" || "$ACTION" == -h || "$ACTION" == help ]] && { usage; exit 0; }
extract

case "$ACTION" in
  list)
    for i in $(seq 1 19); do printf '%3s  %s\n' "$i" "${TITLE[$i]}"; done ;;
  setup)
    num_ok "$N" || { echo "Usage: cka setup <1-19>" >&2; exit 1; }
    if [[ "$N" == 8 ]]; then
      echo "WARNING: task 8 deletes the cluster CNI (Cilium). Other tasks will not work until"
      echo "you install Calico. Best: do task 8 last, or in a fresh Killercoda session."
      read -r -p "Continue? [y/N] " a; [[ "$a" == [yY]* ]] || exit 1
    fi
    run setup "$N"; rc=$?
    echo; run question "$N"
    echo; echo "When done:  cka check $N"
    exit $rc ;;
  question|solution|cleanup)
    num_ok "$N" || { echo "Usage: cka $ACTION <1-19>" >&2; exit 1; }
    run "$ACTION" "$N" ;;
  check|validate)
    if [[ "$N" == all ]]; then
      pass=0; fail=0
      for i in $(seq 1 19); do
        if run check "$i"; then pass=$((pass+1)); else fail=$((fail+1)); fi
      done
      echo; echo -e "\033[0;32mPassed: $pass\033[0m   \033[0;31mFailed: $fail\033[0m   Total: 19"
      (( fail == 0 ))
    else
      num_ok "$N" || { echo "Usage: cka check <1-19|all>" >&2; exit 1; }
      run check "$N"
    fi ;;
  *) usage; exit 1 ;;
esac

# ============================ FIXES (vs. the GitHub repo) ============================
#  Q2  check: chart version 7.7.3 is now verified; solution no longer does an extra helm install
#  Q3  check: "shared emptyDir volume" always passed (empty result counted as success)
#  Q4  check: init vs main compared only CPU request -> now the whole resources block
#      solution: divided by 6, but init containers do not run in parallel -> divide by 3
#  Q5  setup: could not be re-run (service exists) and added --kubelet-insecure-tls twice
#      cleanup: left a broken metrics APIService -> later namespace deletes hang
#  Q7  check: also accepted a value EQUAL to the highest class (1000) - must be 999
#  Q9  check: "inactive" contains "active" -> cri-docker service check always passed
#  Q10 check + task: pod name "nginx" now required/checked
#  Q11 setup: could not be re-run (secret exists); CRDs from release file instead of kustomize URL
#      check: backendRef must be web-service:80 (was: anything)
#  Q12 setup: image moved to registry.k8s.io
#  Q13 check: accepted the too-open policy-y (ipBlock) -> now requires least-permissive policy-z
#      setup/cleanup: files always in ~/network-policies (repo issue #38); no hardcoded pod name
#  Q14 cleanup: left NO default StorageClass -> breaks Q1 afterwards; local-path restored
#  Q15 setup: 2nd run overwrote the backup with the broken manifest
#      cleanup: now actually restores the API server; solution: crictl instead of journalctl
#  Q16 setup: could not be re-run; check: targetPort "http" (named port) was rejected,
#      containerPort 8080 was accepted as "80"
#  Q17 setup: could not be re-run, left tls.key in cwd; cleanup deleted wrong service name
#      solution: "sudo echo >> /etc/hosts" does not work -> "| sudo tee -a"
#  Q18 check: shell-history check was unreliable (repo issue #18) -> uses managedFields
#      (kubectl-patch must own the limits; kubectl-edit/set/replace must not appear)
#  Q19 check: requests like 0.25 / 1Gi crashed the number check; CPU limit change now detected
#  all: "check all" covers 1-19 (repo stopped at 17); task 8 asks before deleting the CNI
