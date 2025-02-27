# Витрина данных для дашборда «Операционная аналитика контакт-центра за 2019 год»


Задача — создать витрину данных для дашборда контакт-центра. Дашборд должен отображать ключевые метрики, такие как время ответа на заявки, количество обработанных заявок и другие показатели, которые помогут оценить эффективность работы отдела.

## Реализация

### Шаг 1: Создание временной таблицы с источниками клиентов

Для начала создадим временную таблицу, которая будет содержать список источников, через которые клиенты обращаются в контакт-центр.
```sql
CREATE TEMPORARY TABLE source_list (name_source TEXT)
;

INSERT INTO source_list (name_source) 
VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4')
;
```

### Шаг 2: Создание представления для первого звонка клиенту

Теперь напишем представление, которое будет содержать информацию о первом звонке клиенту. Мы будем учитывать только первый звонок, так как он является ключевым для расчета времени ответа.

```sql
CREATE OR REPLACE VIEW v_call_first AS
WITH
base_call_all AS(
	SELECT id_client
              ,date_request
              ,date_response
              ,manager
              ,ROW_NUMBER() OVER (PARTITION BY id_client ORDER BY date_response ASC) AS rn
	  FROM all_raw
	 WHERE TRUE
  	   AND action_manager = 'Call'
  	   AND source_client IN (SELECT name_source FROM source_list)
),
work_schedul AS(
	SELECT *
              ,EXTRACT(dow FROM  date_request) AS dow
              ,date_request::date AS date_req
              ,date_request::time AS time_req
          FROM base_call_all
         WHERE rn = 1
),
```

### Шаг 3: Перенос заявки на рабочее время

По бизнес-правилу отсчет времени ответа (SLA) начинается с начала следующей рабочей смены, а не с момента поступления заявки.
```sql
date_registration AS(	
	SELECT ws.id_client
              ,ws.manager
              ,ws.date_request
              ,ws.date_response
	      ,CASE
                   -- Если день выходной или это пятница после 20:00, переносим на первый рабочий день
                   WHEN c.is_working = 0
			OR (c.is_working = 1 AND ws.dow = 5 AND time_req > '20:00:00')
			   THEN (SELECT MIN(c.date_calendar)
				   FROM d_calendar c
				  WHERE c.date_calendar > ws.date_req 
                                    AND c.is_working = 1) + INTERVAL '9 hours'
                   -- Если рабочий день до 09:00, переносим на 9 утра этого дня
		   WHEN c.is_working = 1 AND ws.time_req < '09:00:00'
                        THEN ws.date_req + INTERVAL '9 hours'
                   -- Если рабочий день (кроме пятницы) после 20:00, переносим на 9 утра следующего дня
		   WHEN c.is_working = 1 AND ws.dow != 5 AND ws.time_req > '20:00:00'
		        THEN ws.date_req + INTERVAL '1 days 9 hours'	       		
		   ELSE ws.date_request
               END AS date_registration 
          FROM work_schedul ws
          LEFT JOIN d_calendar c ON ws.date_req = c.date_calendar
)
```

### Шаг 4: Расчет времени обработки заявки

Рассчитываем время между ответом (*date_response*) и регистрацией заявки (*date_registration*). Результат переводим в часы.

```sql
SELECT *
      ,ROUND(EXTRACT(EPOCH FROM date_response - date_registration) / 3600, 2) AS interval_hours
  FROM date_registration
;
```

### Шаг 6: Создание материализованного представления для дашборда

Теперь создадим материализованное представление, которое будет содержать все необходимые данные для дашборда. Это представление будет хранить результаты запроса, что ускорит доступ к данным и улучшит производительность дашборда.

```sql
CREATE OR REPLACE VIEW dash_contact_center AS
SELECT dc.id_client
      ,CASE
           WHEN vcf.date_response IS NULL
                THEN 'wait'
           ELSE 'done'
       END AS call_status
      ,dc.date_request
      ,vcf.date_registration
      ,vcf.date_response
      ,vcf.interval_hours
      ,vcf.manager 
  FROM dict_candidate dc
  LEFT JOIN v_call_first vcf ON vcf.id_client = dc."ID"
 WHERE dc.source_client IN (SELECT name_source FROM source_list)
```

## Заключение

Таким образом была собрана витрина данных для дашборда. В процессе использовались временные таблицы, представления и материализованные представления. \
В скором времени будет доработан алгоритм с учетом выходных и праздничных дней. Также в планах перененсти реализацию с чистого SQL на Python и библиотеки SQLAlchemy и Pandas. Начальные этапы разработки уже можно увидеть в [этом ноутбуке](contact-centr.ipynb).
