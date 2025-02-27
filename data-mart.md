# Витрина данных для дашборда «Операционная аналитика контакт-центра за 2019 год»

**Задача**: Создать витрину данных для дашборда, который отображает ключевые метрики контакт-центра, такие как время ответа на заявки, количество обработанных заявок и другие показатели эффективности работы отдела.


### Шаг 1: Создание временной таблицы с источниками клиентов

Для начала создадим временную таблицу, содержащую список источников, через которые клиенты обращаются в контакт-центр.

```sql
CREATE TEMPORARY TABLE source_list (name_source TEXT);

INSERT INTO source_list (name_source) 
VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4');
```

---

### Шаг 2: Создание представления для первого звонка клиенту

Создадим представление, которое фиксирует информацию о первом звонке клиенту. Это важно для расчета времени ответа.

```sql
CREATE OR REPLACE VIEW v_call_first AS
WITH all_calls AS (
    SELECT 
        id_client,
        date_request,
        date_response,
        manager,
        ROW_NUMBER() OVER (PARTITION BY id_client ORDER BY date_response ASC) AS rn
    FROM all_raw
    WHERE 
        action_manager = 'Call'
        AND source_client IN (SELECT name_source FROM source_list)
),
calls_first AS (
    SELECT 
        *,
        EXTRACT(dow FROM date_request) AS dow,
        date_request::date AS date_req,
        date_request::time AS time_req
    FROM all_calls
    WHERE rn = 1
)
SELECT * FROM calls_first;
```

---

### Шаг 3: Перенос заявки на рабочее время

Согласно бизнес-правилам, отсчет времени ответа (SLA) начинается с начала следующей рабочей смены, а не с момента поступления заявки.

```sql
shift_request AS (
    SELECT 
        cf.id_client,
        cf.manager,
        cf.date_request,
        cf.date_response,
        CASE
            -- Если день выходной или пятница после 20:00, переносим на первый рабочий день
            WHEN dc.is_working = 0
                 OR (dc.is_working = 1 AND cf.dow = 5 AND cf.time_req > '20:00:00')
            THEN (
                SELECT MIN(dc.date_calendar)
                FROM dict_calendar dc
                WHERE dc.date_calendar > cf.date_req 
                  AND dc.is_working = 1
            ) + INTERVAL '9 hours'
            
            -- Если рабочий день до 09:00, переносим на 9 утра этого дня
            WHEN dc.is_working = 1 AND cf.time_req < '09:00:00'
            THEN cf.date_req + INTERVAL '9 hours'
            
            -- Если рабочий день (кроме пятницы) после 20:00, переносим на 9 утра следующего дня
            WHEN dc.is_working = 1 AND cf.dow != 5 AND cf.time_req > '20:00:00'
            THEN cf.date_req + INTERVAL '1 days 9 hours'
            
            -- В остальных случаях оставляем как есть
            ELSE cf.date_request
        END AS date_registration
    FROM calls_first cf
    LEFT JOIN dict_calendar dc ON cf.date_req = dc.date_calendar
)
```

---

### Шаг 4: Расчет времени обработки заявки

Рассчитываем время между ответом (`date_response`) и регистрацией заявки (`date_registration`). Результат переводим в часы.

```sql
SELECT 
    *,
    ROUND(EXTRACT(EPOCH FROM date_response - date_registration) / 3600, 2) AS interval_hours
FROM shift_request;
```

---

### Шаг 5: Создание финального представления для дашборда

Создаем финальное представление, которое будет использоваться в дашборде.

```sql
CREATE OR REPLACE VIEW dash_contact_center AS
SELECT 
    dc.id_client,
    CASE
        WHEN vcf.date_response IS NULL THEN 'wait'
        ELSE 'done'
    END AS call_status,
    dc.date_request,
    vcf.date_registration,
    vcf.date_response,
    vcf.interval_hours,
    vcf.manager
FROM dict_candidate dc
LEFT JOIN v_call_first vcf ON vcf.id_client = dc."ID"
WHERE dc.source_client IN (SELECT name_source FROM source_list);
```

---

## Заключение

В рамках задачи была создана витрина данных для дашборда контакт-центра. В процессе использовались временные таблицы, представления и сложные SQL-запросы для учета бизнес-правил, таких как перенос заявок на рабочее время.

### Планы по развитию:
**Миграция на Python**: Переход с чистого SQL на использование библиотек **SQLAlchemy** и **Pandas** для более гибкой обработки данных. Начальные этапы разработки уже можно увидеть в [этом ноутбуке](contact-centr.ipynb).
