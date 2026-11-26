# Сторонние материалы

- Manrope и PT Serif: SIL Open Font License, тексты в `client/assets/Manrope-OFL.txt` и `PTSerif-OFL.txt`.
- QR-декодер браузера: ZXing JS 0.23.0, локальная копия `client/web/zxing.min.js`, Apache 2.0 в `client/web/vendor/ZXING-LICENSE`.
- Карта: данные © OpenStreetMap contributors, ODbL; исходный рендер OSM France. Ссылки и постоянная атрибуция в карте. Публичные тайлы не обещают SLA и не предзагружаются массово.
- Flutter и Dart, пакеты pub.dev и Python: лицензии соответствующих закреплённых зависимостей сохраняются их дистрибутивами; стандартный реестр Flutter содержит лицензии пакетов.
- Логотип предоставлен заказчиком ранее; используется имеющийся растровый ресурс, а не оригинальный вектор.
- В production нет автоматически опубликованных чужих фотографий. Партнёры загружают изображения, права на публикацию которых проверяет оператор при модерации.
- Рекламные сведения из материалов заказчика импортируются как черновики. Они не заменяют действующий договор партнёра и подтверждение актуальных условий.

## Browser-compatible vector map patches

`client/packages/executor_lib` (upstream 1.1.2) and `client/packages/vector_map_tiles` (upstream 8.0.0) include scoped browser compatibility/request-cache fixes. Their upstream LICENSE files are preserved. Map data attribution remains visible for OpenStreetMap contributors, OpenMapTiles and OpenFreeMap. See MAP_STABILITY.md for changes and limits.
