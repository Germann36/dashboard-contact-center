# Дашборд «Операционная аналитика контакт-центра за 2019 год»
![dash](image/dash-1.jpg)

## Описание
Дашборд «Операционная аналитика контакт-центра за 2019 год» отображает ключевые показатели эффективности (KPI) работы контакт-центра.
Основные метрики включают медианное время обработки обращений, выполнение SLA (Service Level Agreement) и количество обращений.
Панель оснащена интуитивными фильтрами для детализации данных по периодам менеджерам и типам обращений.

## Назначение
Дашборд позволяет:
- **Оценить операционную эффективность**: проанализировать время обработки заявок, уровень обслуживания и загруженность менеджеров.
- **Выявить проблемные зоны**: определить периоды с наибольшим количеством обращений и долгим ожиданием ответа.
- **Оптимизировать ресурсы**: распределить нагрузку между операторами, улучшить процессы обработки обращений и повысить качество обслуживания.

## Реализация
- В документе [development.md](development.md) описана разработка дашборда в **Power BI**. \
  Рассмотрены этапы подключения к данным, настройка визуализаций и фильтров.
- В документе [data-mart.md](data-mart.md) пошагово разобран процесс создания витрины данных в **PostgreSQL**. \
  Таблица денормализована для поддержки разнообразных фильтров.

## Примечание
Данные являются искусственными и созданы для демонстрационных целей. Любые совпадения случайны.
