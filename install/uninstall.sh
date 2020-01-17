kubectl -n istio-system get configmap istio-sidecar-injector -o yaml | sed "s/otdd\/proxyv2:1.2.2-alpha.0/istio\/proxyv2:1.2.2/g"| kubectl apply -f -
kubectl -n istio-system rollout restart deploy/istio-sidecar-injector
for i in artifacts/crd*yaml; do kubectl delete -f $i; done
kubectl delete -f otdd-controller.yaml
for i in artifacts/istio-mixer*.yaml; do kubectl delete -f $i; done
kubectl delete -f otdd-adapter.yaml
kubectl delete -f namespace.yaml
