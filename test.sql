--Назначим переменную по источнику клиента
CREATE TEMPORARY TABLE source_list (name_source TEXT)
;
INSERT INTO source_list (name_source) VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4')
;



--Выборка клиентов по перечисленным источникам
CREATE OR REPLACE VIEW client_all AS
SELECT *
  FROM base_client
 WHERE TRUE 
   AND promotion IN (SELECT name_source FROM source_list)
;



--Выборка по всем клиентам, которым позвонили
CREATE OR REPLACE VIEW client_callfirst AS
WITH

--Пронумируем все звонки клиентам, чтобы найти первый
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

--Оставляем только первый звонок
t_work_sched AS(
	SELECT *
	 	  ,EXTRACT(dow FROM create_date_client) AS dow --Достаем день недели из даты для следующего запроса (воскресенье — это 0)
	   	  ,create_date_client::time AS oclock
  	  FROM base_call_all
 	 WHERE rn = 1
),

--Теперь по бизнес-правилу перекидываем поступление заявки с нерабочего времени на рабочее, для корректного счета SLA
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

--Переводим полученное время в часы и минуты
SELECT *
	  ,ROUND(EXTRACT(EPOCH FROM create_date_status - work_app) / 3600, 2) AS interval_hours
	  ,ROUND(EXTRACT(EPOCH FROM create_date_status - work_app) / 60, 2) AS interval_minutes
  FROM t_work_app
; 



--Мэтчим всех юнитов в базе с теми, кому позвонили
CREATE OR REPLACE MATERIALIZED VIEW dash_contact_center AS
SELECT ca.id_client
	  ,CASE 
	        WHEN bucf.create_date_status IS NULL 
	             THEN 'Не позвонили'
	  	    ELSE 'Позвонили'
	    END AS "Результат"
	  ,bucf.manager AS "Менеджер"
	  ,ca.create_date_client AS "Дата поступления заявки" --Дата, когда заявка попала в систему
	  ,bucf.work_app AS "Дата регистрации заявки" --Дата для начала отсчета SLA (только будние дни и рабочее время)
	  ,bucf.create_date_status AS "Дата звонка" --Дата, когда менеджер позвонил клиенту
	  ,bucf.interval_hours AS "Интервал в часах" --Разница между датой регистрации заявки и датой звонка в часах
	  ,bucf.interval_minutes AS "Интервал в минутах" --Разница между датой регистрации заявки и датой звонка в минтуах
  FROM client_all ca
  LEFT JOIN base_unit_callfirst bucf ON bucf.id_client = ca.id_client
 WHERE bucf.interval_hours IS NOT NULL

