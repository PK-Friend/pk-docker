# pk-docker

TDM의 R 계산 패키지를 설치한 베이스 이미지를 로컬에서 빌드해 GHCR에 올립니다.
`pk-mono`는 이 이미지를 재사용합니다.

## 빌드 및 업로드

Docker Buildx와 `gh` CLI가 필요합니다.

- `CR_USER`: GitHub ID
- `CR_PAT`: [GitHub 안내에 따라 생성한 Personal access token (classic)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic). `read:packages`, `write:packages` 권한을 선택합니다.

```bash
export CR_USER="your-github-id"
export CR_PAT="your-personal-access-token"
bash tdm-build-base/build.sh
```

빌드와 검증을 통과하면 `tdm-build-base/VERSION`의 버전 태그로 업로드하고,
가장 최신 버전이면 `latest`도 갱신합니다. 두 환경 변수가 없으면 로컬 빌드·검증만 합니다.

기존 버전은 덮어쓰지 않으므로 변경 시 `VERSION`을 올립니다. 업로드는 한 번에 하나씩 실행합니다.
첫 업로드 후 GHCR 패키지를 **public**으로 설정해야 `pk-mono`가 로그인 없이 가져올 수 있습니다.

## 이미지 사용

이미지: `ghcr.io/pk-friend/pk-docker/tdm-build-base:1.0.0`

Ubuntu 22.04 / `linux/amd64` 기반이며, R과 계산 패키지 버전은
[Dockerfile](tdm-build-base/Dockerfile)에서 관리합니다.

`pk-mono/TDM`에서는 다음처럼 사용합니다.

```dockerfile
ARG TDM_BUILD_BASE=ghcr.io/pk-friend/pk-docker/tdm-build-base:1.0.0
FROM ${TDM_BUILD_BASE} AS packages
FROM packages AS app
```

앱 모델 컴파일과 최종 이미지의 컴파일러 제거는 `pk-mono`에서 수행합니다.
이 저장소의 CI는 스크립트 검사만 실행하며, 이미지 빌드·업로드는 로컬에서 수행합니다.
