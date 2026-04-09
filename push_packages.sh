#!/bin/bash
product="${1:-emqx}"
version="${2:-5.0.0}"
version=${version#v}
version=${version#e}

get_os_info() {
	os_version=$(echo ${1} | rev | cut -d'-' -f2 | rev)
	case $os_version in
	ubuntu16.04)
		os_name="ubuntu"
		os_version="xenial"
		;;
	ubuntu18.04)
		os_name="ubuntu"
		os_version="bionic"
		;;
	ubuntu20.04)
		os_name="ubuntu"
		os_version="focal"
		;;
	ubuntu22.04)
		os_name="ubuntu"
		os_version="jammy"
		;;
	debian9)
		os_name="debian"
		os_version="stretch"
		;;
	debian10)
		os_name="debian"
		os_version="buster"
		;;
	debian11)
		os_name="debian"
		os_version="bullseye"
		;;
	amzn2)
		os_name="el"
		os_version="6"
		;;
	el7)
		os_name="el"
		os_version="7"
		;;
	el8)
		os_name="el"
		os_version="8"
		;;
	el9)
		os_name="el"
		os_version="9"
		;;
	*)
		echo "Unknown OS version: $os_version"
		exit 1
		;;
	esac
	os="$os_name/$os_version"
}

delete_package() {
	repo_name="${1}"
	package_version="${2}"

	urls=$(curl -s https://${PACKAGECLOUD_TOKEN}:@packagecloud.io/api/v1/repos/emqx/${repo_name}/search.json\?q=${package_version}\&per_page=100 | jq -r '.[] | select(.version == "'${package_version}'") | .distro_version + "=" + .filename')
	for destroy_url in $urls; do
		destroy_url=$(echo $destroy_url | sed 's/\(.*\)=\(.*\)/\1 \2/')
		package_cloud yank emqx/$repo_name/$destroy_url
	done
}

# for nanomq & neuron
push_packages() {
	if [ "$product" == "neuron" ]; then
		product_repo="emqx/neuron-modules"
	elif [ "$product" == "nanomq" ]; then
		product_repo="nanomq/nanomq"
	else
		echo "> Unknown product: $product"
		exit 1
	fi
	assets=$(curl -s -H "Authorization: token $GIT_TOKEN" https://api.github.com/repos/$product_repo/releases/tags/${version} | jq -r '.assets[] | .name' | grep -E '\.rpm$|\.deb$')
	if [ -z "$assets" ]; then
		echo "> No assets found"
		exit 1
	fi
	download_prefix="https://github.com/$product_repo/releases/download/${version}"
	folder_name="${product}-${version}"

	if [ ! -d $folder_name ]; then
		mkdir $folder_name
	else
		echo "> $folder_name folder already exists"
		exit 1
	fi

	delete_package $product $version

	for asset in ${assets[@]}; do
		if [[ $asset =~ "sqlite" ]]; then
			continue
		fi

		if [[ $asset =~ "msquic" ]]; then
			continue
		fi

		if [[ $asset =~ "full" ]]; then
			continue
		fi

		if [[ $asset =~ "riscv64" ]]; then
			continue
		fi

		echo "> Downloading $asset"
		curl -L -s -X GET "${download_prefix}/${asset}" -H 'Accept: application/octet-stream' -H "Authorization: token $GIT_TOKEN" -o "${folder_name}/${asset}"

		case $asset in
		*.rpm)
			package_cloud push emqx/${product}/rpm_any/rpm_any ${folder_name}/${asset} || true
			;;
		*.deb)
			package_cloud push emqx/${product}/any/any ${folder_name}/${asset} || true
			;;
		*)
			echo "> Unknown asset type: $asset"
			exit 1
			;;
		esac
	done
}

push_emqx() {
	assets=$(curl -s -H "Authorization: token $GIT_TOKEN" https://api.github.com/repos/emqx/emqx/releases/tags/v${version} | jq -r '.assets[] | .name' | grep -E '\.rpm$|\.deb$')
	if [ -z "$assets" ]; then
		echo "> No assets found"
		exit 1
	fi
	download_prefix="https://github.com/emqx/emqx/releases/download/v${version}"
	folder_name="emqx-${version}"

	if [ ! -d $folder_name ]; then
		mkdir $folder_name
	else
		echo "> $folder_name folder already exists"
		exit 1
	fi

	delete_package "emqx" $version

	for asset in ${assets[@]}; do
		if [[ $asset =~ "emqx-edge-" ]]; then
			continue
		fi

		if [[ $asset =~ "otp" ]] && [[ $version =~ ^5 ]]; then
			continue
		fi

		echo "> Downloading $asset"
		curl -s -L "${download_prefix}/${asset}" -o "${folder_name}/${asset}"
		get_os_info $asset
		package_cloud push emqx/emqx/$os ${folder_name}/${asset}
	done
}

push_emqx_enterprise() {
	assets=$(curl -s -H "Authorization: token $GIT_TOKEN" https://api.github.com/repos/emqx/emqx-enterprise/releases/tags/e${version} |  jq '[.assets[] | {name: .name, url: .url} | select(.name | endswith(".deb") or endswith(".rpm"))]')
	if [ -z "$assets" ]; then
		echo "> No assets found"
		exit 1
	fi
	assets_num=$(echo $assets | jq '. | length')
	folder_name="emqx-enterprise-${version}"

	if [ ! -d $folder_name ]; then
		mkdir $folder_name
	else
		echo "> $folder_name folder already exists"
		exit 1
	fi

	delete_package "emqx-enterprise" $version

	for asset_index in `seq 0 $(($assets_num - 1))`; do
		asset_name=$(echo $assets | jq -r ".[$asset_index].name")
		asset_url=$(echo $assets | jq -r ".[$asset_index].url")
		
		if [[ $asset_name =~ "otp" ]] && [[ $version =~ ^5 ]]; then
			continue
		fi

		echo "> Downloading $asset_name"
		curl -L -s -X GET $asset_url -H 'Accept: application/octet-stream' -H "Authorization: token $GIT_TOKEN" -o "${folder_name}/${asset_name}"
		get_os_info $asset_name
		package_cloud push emqx/emqx-enterprise/$os ${folder_name}/${asset_name}
	done
}

main() {
	if [ $product == "emqx" ]; then
		push_emqx
	elif [ $product == "enterprise" ]; then
		push_emqx_enterprise
	else
		push_packages
	fi
}

main
