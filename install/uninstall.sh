kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config" |awk '{gsub(/name:[ ]+istio-proxy.+[ ]{4}ports/,"name: istio-proxy\\n  {{- if contains \\\"/\\\" .Values.global.proxy.image }}\\n    image: \\\"{{ annotation .ObjectMeta `sidecar.istio.io/proxyImage` .Values.global.proxy.image }}\\\"\\n  {{- else }}\\n    image: \\\"{{ annotation .ObjectMeta `sidecar.istio.io/proxyImage` .Values.global.hub }}/{{ .Values.global.proxy.image }}:{{ .Values.global.tag }}\\\"\\n  {{- end }}\\n    ports"); print $0}' > .otdd_tmp_uninstall
VALUE=`cat .otdd_tmp_uninstall`
rm -rf .otdd_tmp_uninstall
kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config=$VALUE" | kubectl apply -f -
kubectl -n istio-system rollout restart deploy/istio-sidecar-injector
for i in artifacts/crd*yaml; do kubectl delete -f $i; done
kubectl delete -f artifacts/otdd-controller.yaml
for i in artifacts/istio-mixer*.yaml; do kubectl delete -f $i; done
kubectl delete -f artifacts/otdd-adapter.yaml
kubectl delete -f artifacts/otdd-server.yaml
kubectl delete -f artifacts/namespace.yaml
