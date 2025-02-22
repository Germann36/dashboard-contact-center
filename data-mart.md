# Витрина данных для дашборда контакт-центра

## Общие моменты
Надо сделать витрину для дашборда контакт-центра.

## Реализация
Сначала назначим переменную по источнику клиента. Сделаем это через временную таблицу.
```sql
CREATE TEMPORARY TABLE source_list (name_source TEXT)
;
INSERT INTO source_list (name_source) VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4')
;
```

Далее выберем из базы клиентов всех, кто обратился через указанные источники. \
Создаем обычное представление, чтобы в дальнейшем было удобно работать с получившейся таблицей.
```sql
CREATE OR REPLACE VIEW client_requests AS
SELECT *
  FROM all_client
 WHERE TRUE 
   AND promotion IN (SELECT name_source FROM source_list)
```

Теперь создадим представление, которое:
1. Покажет клиентов, которым менеджеры ответили на заявку. В расчет будем брать только первый звонок.
2. Будет перекидывать дату заявки с нерабочего времени на рабочее для корректного отсчета SLA.

Создаем представление, в которой будем использовать CTE (обобщенное табличное выражение).
```sql
CREATE OR REPLACE VIEW client_callfirst AS
WITH
```

Выведем необходимые поля и пронумируем звонки. Стоит учитывать, что клиентов берем по определенному списку источников, которые мы указали во временной таблице.
```sql
base_call_all AS(
	SELECT id_client
		  ,create_date_client --Дата, когда заявка упала в систему
		  ,source_client
		  ,status_client
		  ,create_date_status --Дата, когда заявке проставили статус
		  ,manager
		  ,ROW_NUMBER() OVER (PARTITION BY id_client ORDER BY create_date_status ASC) AS rn --Ранжируем звонки клиентам от старых к новым
	  FROM client_status
	 WHERE TRUE
  	   AND status_client LIKE 'Call:%'
  	   AND source_client IN (SELECT name_source FROM source_list)
),
```

Оставляем только первый звонок
```sql
t_work_sched AS(
	SELECT *
	 	  ,EXTRACT(dow FROM create_date_client) AS dow --Достаем день недели из даты для следующего запроса (воскресенье — это 0)
	   	  ,create_date_client::time AS oclock
  	  FROM base_call_all
 	 WHERE rn = 1
),
```

Теперь реализуем алгоритм, который проверяет время обращения. Если заявка упала в выходные или нерабочее время, дата смещается на начало смены менеджеров.
```sql
t_work_app AS(
	SELECT *
	  	  ,CASE 
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
```

Сразу расчитаем разницу между датой регистрации заявки и датой ответа. Переведем результат в часы и минуты для настройки гранулярности в BI-системе.
```sql
SELECT *
	  ,ROUND(EXTRACT(EPOCH FROM create_date_status - work_app) / 3600, 2) AS interval_hours
	  ,ROUND(EXTRACT(EPOCH FROM create_date_status - work_app) / 60, 2) AS interval_minutes
  FROM t_work_app
; 
```

Теперь построим таблицу, которая покажет, кому менеджеры ответили, а кому нет. \
Также переименнуем столбцы для удобства работы бизнес-пользователей.
Для работы используем материальное представление, так как оно хранит резульатаы запроса, что ускоряет доступ к данным. Как раз то, что нужно для хорошего дашборда.
```sql
CREATE OR REPLACE MATERIALIZED VIEW dash_contact_center AS
SELECT cr.id_client
	  ,CASE 
	        WHEN bucf.create_date_status IS NULL 
	             THEN 'Не позвонили'
	  	    ELSE 'Позвонили'
	    END AS response
	  ,bucf.manager AS manager_id
	  ,cr.create_date_client AS date_request --Дата, когда заявка попала в систему
	  ,bucf.work_app AS date_registration --Дата для начала отсчета SLA (только будние дни и рабочее время)
	  ,bucf.create_date_status AS date_response --Дата, когда менеджер позвонил клиенту
	  ,bucf.interval_hours AS interval_hours --Разница между датой регистрации заявки и датой звонка в часах
	  ,bucf.interval_minutes AS interval_minutes --Разница между датой регистрации заявки и датой звонка в минтуах
  FROM client_requests cr
  LEFT JOIN base_unit_callfirst bucf ON bucf.id_client = cr.id_client
 WHERE bucf.interval_hours IS NOT NULL
```

----
Таким образом, мы сделали витрину, которая будет идти в дашборд. \
Данные могут обновляться ежедневнего через планировщик.
