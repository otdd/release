usage(){
        echo "Usage: uninstall.sh -v istio-version"
        echo ""
        echo -e "\texamples: \t\tunstall.sh -v 1.2.2"
        exit 1
}

while getopts v: option
do
 case "${option}"
 in
 v) ISTIO_VERSION=${OPTARG};;
 esac
done

if [ -z "$ISTIO_VERSION" ]
then
  usage
fi

kubectl -n istio-system get configmap istio-sidecar-injector -o yaml | sed "s/otdd\/proxyv2:$ISTIO_VERSION-otdd.0.1.0/istio\/proxyv2:$ISTIO_VERSION/g"| kubectl apply -f -
kubectl -n istio-system rollout restart deploy/istio-sidecar-injector
for i in artifacts/crd*yaml; do kubectl delete -f $i; done
kubectl delete -f artifacts/otdd-controller.yaml
for i in artifacts/istio-mixer*.yaml; do kubectl delete -f $i; done
kubectl delete -f artifacts/otdd-adapter.yaml
kubectl delete -f artifacts/namespace.yaml
