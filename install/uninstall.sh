for i in artifacts/crd*yaml; do kubectl delete -f $i; done
kubectl delete -f artifacts/otdd-controller.yaml
for i in artifacts/before_1.5/*.yaml; do kubectl delete -f $i; done
kubectl delete -f artifacts/otdd-adapter.yaml
kubectl delete -f artifacts/otdd-server.yaml
kubectl delete -f artifacts/namespace.yaml
