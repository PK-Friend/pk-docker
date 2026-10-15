# pk-docker

PK-Friend 서비스의 공통 Docker 빌드 이미지를 관리합니다.
`Atflow-Corp/docker`의 이미지별 디렉터리와 로컬 `build.sh` 구성을 참고했습니다.

## TDM 의존성 이미지

`ghcr.io/pk-friend/pk-docker/tdm-build-base`는 `pk-mono/TDM`의 패키지 설치 단계를
분리한 **빌드용 이미지**입니다. 패키지 컴파일은 이 이미지를 발행할 때 수행하며,
일반적인 TDM 앱 빌드는 설치가 끝난 이미지를 재사용합니다.

| 항목 | 버전 |
| --- | --- |
| 이미지 | `tdm-build-base/VERSION`: `1.0.0` |
| OS / 아키텍처 | Ubuntu 22.04 / `linux/amd64` |
| R | 4.6.1 |
| rxode2ll | 2.0.16 |
| rxode2 | 5.1.7.1 |
| nlmixr2est | 7.1.0 |
| nlmixr2 | 7.0.1 |
| mrgsolve | 2.0.1 |
| NonCompart | 0.8.4 |

컴파일러, 개발 헤더, 한국어 locale, TDM 공통 R 패키지를 포함합니다.
`RCurl` 설치에 필요한 `curl-config`는 `libcurl4-openssl-dev`로 제공합니다.
앱 코드·약물 모델·모델 캐시는 포함하지 않습니다. 모델 컴파일과 warmup, 최종
이미지에서 컴파일러를 제거하는 과정은 `pk-mono`에서 수행합니다.

핵심 계산 패키지는 고정하지만 지원 패키지와 OS 저장소는 snapshot이 아닙니다.
빌드 시점의 설치 목록은 `/usr/local/share/tdm-build-base/`의
`NUMERICAL_VERSIONS.tsv`, `R_PACKAGES.tsv`, `DPKG_PACKAGES.tsv`에 기록합니다.
기존 소비 경로인 `/tmp/tdm-numerical-lock.tsv`도 제공합니다.

## 로컬 빌드와 검증

Docker Buildx가 필요하며, Apple Silicon에서도 배포 대상인 `linux/amd64`로 빌드합니다.

```bash
bash tests/test-build.sh
bash tests/test-publish.sh
bash tests/test-install-apt-packages-with-retries.sh
bash tdm-build-base/build.sh
```

`build.sh`는 `VERSION`에 적힌 태그로 로컬 이미지를 만든 뒤, 네트워크를 끈 컨테이너에서
패키지 버전·로딩 및 합성 데이터 계산을 검사합니다. 로그인이나 업로드는 수행하지 않습니다.
이 검사는 베이스 이미지의 기본 동작 검증이며, TDM 전체 회귀 테스트나 임상 검증을 대체하지 않습니다.

## GHCR 발행

PR과 `main` push는 빌드·검증만 합니다. `tdm-build-base/vX.Y.Z` 태그를 push하면
같은 검증을 통과한 **동일 이미지**를 artifact로 전달해 GHCR에 업로드합니다.
발행 단계에서는 다시 빌드하지 않습니다. 인증은 해당 저장소의 `GITHUB_TOKEN`과
`packages: write` 권한을 사용하며 별도 PAT를 저장하지 않습니다.

1. 패키지·OS 의존성 변경과 함께 `tdm-build-base/VERSION`을 올리고 PR을 병합합니다.
2. 발행할 커밋에 `VERSION`과 일치하는 태그를 붙이고 그 태그 하나를 push합니다.

   ```bash
   git tag tdm-build-base/v1.0.0
   git push origin tdm-build-base/v1.0.0
   ```

3. Actions의 `build`, `publish` 성공 및 GHCR 태그를 확인합니다.

이미 존재하는 버전 태그는 덮어쓰지 않습니다. `1.0.0` 같은 버전 태그와 `latest`를
함께 발행하되, 과거 버전 발행이 `latest`를 이전 버전으로 되돌리지는 않습니다.
동일 버전으로 재실행하면 발행을 거부하므로 수정은 새 버전으로 발행합니다.

**첫 발행 후 GHCR 패키지의 visibility를 public으로 설정해야 합니다.** 공개 GitHub
저장소라도 새 GHCR 패키지는 private일 수 있습니다. `pk-mono`는 GHCR 로그인 없이
베이스 이미지를 가져오므로, 다음과 같이 별도 Docker 인증 설정으로 익명 pull을 확인합니다.

```bash
docker_config=$(mktemp -d)
DOCKER_CONFIG="$docker_config" docker pull --platform linux/amd64 \
  ghcr.io/pk-friend/pk-docker/tdm-build-base:1.0.0
rm -rf "$docker_config"
```

## pk-mono에서 사용

첫 이미지를 발행하고 익명 pull을 확인한 뒤 소비 PR을 병합합니다. TDM에서는
`latest` 대신 명시한 버전을 사용합니다.

```dockerfile
ARG TDM_BUILD_BASE=ghcr.io/pk-friend/pk-docker/tdm-build-base:1.0.0
FROM ${TDM_BUILD_BASE} AS packages
FROM packages AS app
```

이미지 업데이트 시 `TDM_BUILD_BASE`와 필요시 최종 scratch stage의 R/패키지 버전
환경 변수를 함께 갱신하고, `pk-mono`의 runtime API·모델 회귀 검증을 수행합니다.
패키지 버전이 같아도 지원 라이브러리나 OS 업데이트가 있으면 새 이미지 버전을 발행합니다.
