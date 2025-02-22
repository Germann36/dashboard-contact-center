# Витрина данных для дашборда «Операционная аналитика контакт-центра за 2019 год»

В этой статье мы рассмотрим, как создать витрину данных для дашборда, который будет отображать операционную аналитику контакт-центра за 2019 год. Витрина данных — это структурированный набор данных, оптимизированный для анализа и визуализации. Мы будем использовать SQL для создания временных таблиц, представлений и материализованных представлений, которые помогут нам подготовить данные для дальнейшего анализа.

## Общие моменты

Наша задача — создать витрину данных, которая будет использоваться для построения дашборда контакт-центра. Дашборд должен отображать ключевые метрики, такие как время ответа на заявки, количество обработанных заявок и другие показатели, которые помогут оценить эффективность работы контакт-центра.

## Реализация

### Шаг 1: Создание временной таблицы с источниками клиентов

Для начала создадим временную таблицу, которая будет содержать список источников, через которые клиенты обращаются в контакт-центр. Это позволит нам фильтровать данные по конкретным источникам.

```sql
CREATE TEMPORARY TABLE source_list (name_source TEXT);

INSERT INTO source_list (name_source) 
VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4');
```

### Шаг 2: Создание представления для отфильтрованных заявок

Далее создадим представление, которое будет содержать все заявки клиентов, обратившихся через указанные источники. Это представление упростит дальнейшую работу с данными.

```sql
CREATE OR REPLACE VIEW client_requests AS
SELECT id_client,
       create_date_client
  FROM all_client
 WHERE promotion IN (SELECT name_source FROM source_list);
```

### Шаг 3: Создание представления для первого звонка клиенту

Теперь создадим представление, которое будет содержать информацию о первом звонке клиенту. Мы будем учитывать только первый звонок, так как он является ключевым для расчета времени ответа.

```sql
CREATE OR REPLACE VIEW client_callfirst AS
WITH base_call_all AS (
    SELECT id_client,
           create_date_client, -- Дата, когда заявка упала в систему
           source_client,
           status_client,
           create_date_status, -- Дата, когда заявке проставили статус
           manager,
           ROW_NUMBER() OVER (PARTITION BY id_client ORDER BY create_date_status ASC) AS rn -- Ранжируем звонки клиентам от старых к новым
      FROM client_status
     WHERE status_client LIKE 'Call:%'
       AND source_client IN (SELECT name_source FROM source_list)
),
t_work_sched AS (
    SELECT *,
           EXTRACT(dow FROM create_date_client) AS dow, -- Достаем день недели из даты для следующего запроса (воскресенье — это 0)
           create_date_client::time AS oclock
      FROM base_call_all
     WHERE rn = 1
),
t_work_app AS (
    SELECT *,
           CASE 
               WHEN dow NOT IN (6, 0) AND (oclock BETWEEN '00:00:00' AND '08:59:59') 
                    THEN CONCAT(create_date_client::date, ' ', '09:00:00')::timestamp
               WHEN dow NOT IN (5, 6, 0) AND (oclock BETWEEN '20:00:01' AND '23:59:59') 
                    THEN create_date_client::date + INTERVAL '1 day 9 hours'
               WHEN dow IN (5) AND (oclock BETWEEN '20:00:01' AND '23:59:59') 
                    THEN create_date_client::date + INTERVAL '3 day 9 hours'
               WHEN dow IN (6)
                    THEN create_date_client::date + INTERVAL '2 day 9 hours'
               WHEN dow IN (0)
                    THEN create_date_client::date + INTERVAL '1 day 9 hours'
               ELSE create_date_client
           END AS work_app
      FROM t_work_sched
)
SELECT *,
       ROUND(EXTRACT(EPOCH FROM create_date_status - work_app) / 3600, 2) AS interval_hours,
       ROUND(EXTRACT(EPOCH FROM create_date_status - work_app) / 60, 2) AS interval_minutes
  FROM t_work_app;
```

### Шаг 4: Создание материализованного представления для дашборда

Теперь создадим материализованное представление, которое будет содержать все необходимые данные для дашборда. Это представление будет хранить результаты запроса, что ускорит доступ к данным и улучшит производительность дашборда.

```sql
CREATE OR REPLACE MATERIALIZED VIEW dash_contact_center AS
SELECT cr.id_client,
       CASE 
           WHEN ccf.create_date_status IS NULL 
                THEN 'Не позвонили'
           ELSE 'Позвонили'
       END AS response,
       ccf.manager AS manager_id,
       cr.create_date_client AS date_request, -- Дата, когда заявка попала в систему
       ccf.work_app AS date_registration, -- Дата для начала отсчета SLA (только будние дни и рабочее время)
       ccf.create_date_status AS date_response, -- Дата, когда менеджер позвонил клиенту
       ccf.interval_hours AS interval_hours, -- Разница между датой регистрации заявки и датой звонка в часах
       ccf.interval_minutes AS interval_minutes -- Разница между датой регистрации заявки и датой звонка в минутах
  FROM client_requests cr
  LEFT JOIN client_callfirst ccf ON ccf.id_client = cr.id_client
 WHERE bucf.interval_hours IS NOT NULL;
```

## Заключение

В этой статье мы рассмотрели, как создать витрину данных для дашборда контакт-центра. Мы использовали временные таблицы, представления и материализованные представления для подготовки данных, которые будут использоваться для анализа и визуализации. Теперь у вас есть структурированный набор данных, который можно использовать для построения интерактивного дашборда, помогающего оценить эффективность работы контакт-центра.
