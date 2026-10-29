<p align="center">
  <img src=".assets/icon.png" height="100" alt="Klopydrome">
</p>

<h1 align="center">Klopydrome</h1>

Экспериментальный "Apple Music" ahh клиент написаный слопом за 0 тугриков. Работает с [Navidrome][1] и [Subsonic][2]-совместимыми серверами. Приложение написано на SwiftUI, работает с macOS 14.4. Имеет риск адекватной работы.
<p align="center">
  <img src=".assets/preview1.webp" alt="Интерфейс. Карточка альбома, текст">
  <h5>ну вроде норм я попользовался</h5>
</p>

## Фишки

<div>
  <img src=".assets/preview2.webp" height="400" align="left" style="margin-right: 20px">

  <ul>
    <br>
    <li>Кушает ~200-400 мегабайт ОЗУ;</li>
    <li>Кэширование аудио и обложек;</li>
    <li>Поддержка транскодинга;</li>
    <li>Оффлайн-режим;</li>
    <li>Синхронизированный текст (и extended LRC тоже);</li>
    <li>Создание нескучных плейлистов (и смарт-плейлистов);</li>
    <li>Поддержка Discord RPC;</li>
    <li>Crossfade и поддержка ReplayGain;</li>
    <li>Мини-плеер;</li>
    <li>Серверные функции (quick scan, менеджер ссылок);</li>
    <li>Слоп.</li>
  </ul>
</div>

<br clear="all">

<p align="center">
  <img src=".assets/preview3.webp" alt="Интерфейс. Карточка альбома">
  <h5>даже вроде не лагает и бобами не отдаёт</h5>
</p>

## Сборка

Нужны **macOS 14.4+**, Xcode 16 или новее и Homebrew. Скрипты находятся в `scripts/` и запускаются из корня репозитория.

На чистом клоне сначала соберите локальный аудиодвижок на базе `Libmpv`. Если `vendor/MPVKit-Audio/dist/release/xcframework/Libmpv.xcframework` уже существует, этот шаг можно пропустить.

```sh
# сабмодуль движка + пакеты для сборки
git submodule update --init
brew install nasm meson ninja cmake pkg-config wget git

# сама сборка
./scripts/build-mpvkit-audio.sh
```

Затем соберите приложение:

```sh
./scripts/build-app.sh # или: make app
```

Скрипт запускает линтер и нужный тест, собирает debug-версию и подписывает её ad-hoc. Готовое приложение будет лежать в `.build/app/Klopydrome.app`.

Для release-версии:

```sh
./scripts/build-app.sh --release [--no-test --no-lint] # или: make release
```

Сборка zip-архива для релиза (в `dist/`):

```sh
make dist # или: ./scripts/package-release.sh
```

Отдельно:

```sh
swift test # все тесты (или: make test)
./scripts/lint.sh # линтер
```

## License

[MIT](LICENSE)

[1]: https://www.navidrome.org/
[2]: https://www.navidrome.org/docs/developers/subsonic-api/