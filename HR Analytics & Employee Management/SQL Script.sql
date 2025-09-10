CREATE DATABASE hr_analytics;
USE hr_analytics;

-- Creating tables
CREATE TABLE departments (
    dept_id INT PRIMARY KEY,
    dept_name VARCHAR(50),
    location VARCHAR(50)
);

CREATE TABLE employees (
    employee_id INT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    hire_date DATE,
    job_title VARCHAR(100),
    dept_id INT,
    salary DECIMAL(10,2),
    manager_id INT,
    status VARCHAR(20) DEFAULT 'Active',
    termination_date DATE NULL,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id),
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id)
);

CREATE TABLE performance_reviews (
    review_id INT PRIMARY KEY,
    employee_id INT NOT NULL,
    review_date DATE NOT NULL,
    reviewer_id INT NOT NULL,
    performance_score DECIMAL(3,2) NOT NULL,  -- 1.00 to 5.00
    goals_met BIT NOT NULL,                   -- 0 = No, 1 = Yes
    promotion_ready BIT NOT NULL,             -- 0 = No, 1 = Yes
    comments VARCHAR(MAX) NULL,
    CONSTRAINT FK_Performance_Employee FOREIGN KEY (employee_id) 
        REFERENCES employees(employee_id),
    CONSTRAINT FK_Performance_Reviewer FOREIGN KEY (reviewer_id) 
        REFERENCES employees(employee_id)
);


CREATE TABLE training_programs (
    program_id INT PRIMARY KEY,
    program_name VARCHAR(100),
    duration_hours INT,
    cost_per_employee DECIMAL(8,2)
);

CREATE TABLE employee_training (
    training_id INT PRIMARY KEY,
    employee_id INT NOT NULL,
    program_id INT NOT NULL,
    completion_date DATE NOT NULL,
    score DECIMAL(5,2) NOT NULL,
    passed BIT NOT NULL,  -- 0 = No, 1 = Yes
    CONSTRAINT FK_EmployeeTraining_Employee FOREIGN KEY (employee_id) 
        REFERENCES employees(employee_id),
    CONSTRAINT FK_EmployeeTraining_Program FOREIGN KEY (program_id) 
        REFERENCES training_programs(program_id)
);

-- Viewing Tables
SELECT * FROM departments;
SELECT * FROM employees;
SELECT * FROM performance_reviews;
SELECT * FROM training_programs;
SELECT * FROM employee_training;


-- HR ANALYTICS QUERIES

-- 1. Employee Turnover Analysis
WITH turnover_stats AS (
    SELECT 
        d.dept_name,
        COUNT(e.employee_id) AS total_employees,
        SUM(CASE WHEN e.status = 'Terminated' THEN 1 ELSE 0 END) AS terminated_employees,
        ROUND(
            100.0 * SUM(CASE WHEN e.status = 'Terminated' THEN 1 ELSE 0 END)
            / NULLIF(COUNT(e.employee_id), 0), 
        1) AS turnover_rate_num
    FROM departments d
    LEFT JOIN employees e ON d.dept_id = e.dept_id
    GROUP BY d.dept_id, d.dept_name
)
SELECT 
    dept_name,
    total_employees,
    terminated_employees,
    -- formatted as "10.1%"
    COALESCE(CONCAT(CAST(turnover_rate_num AS DECIMAL(5,1)), '%'), '0.0%') AS turnover_rate,
    CASE 
        WHEN COALESCE(turnover_rate_num, 0) > 20 THEN 'High Risk'
        WHEN COALESCE(turnover_rate_num, 0) > 10 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_level
FROM turnover_stats
ORDER BY turnover_rate_num DESC;

-- 2. Salary Analysis by Department and Position
-- By Job title
SELECT 
    d.dept_name,
    e.job_title,
    COUNT(e.employee_id) as employee_count,
    MIN(e.salary) as min_salary,
    MAX(e.salary) as max_salary,
    CAST(AVG(e.salary) AS DECIMAL(18,2)) AS avg_salary, -- Playing with different functions 
    ROUND(STDEV(e.salary),2) as salary_std_dev
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE e.status = 'Active'
GROUP BY d.dept_name, e.job_title
ORDER BY d.dept_name, avg_salary DESC;

-- By Department
SELECT 
    d.dept_name,
    COUNT(e.employee_id) as employee_count,
    MIN(e.salary) as min_salary,
    MAX(e.salary) as max_salary,
    CAST(AVG(e.salary) AS DECIMAL(18,2)) AS avg_salary,
    ROUND(STDEV(e.salary),2) as salary_std_dev
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE e.status = 'Active'
GROUP BY d.dept_name
ORDER BY d.dept_name, avg_salary DESC;

-- 3. Performance Review Analysis
WITH performance_trends AS (
    SELECT 
        e.employee_id,
        CONCAT(e.first_name, ' ', e.last_name) as employee_name,
        e.job_title,
        d.dept_name,
        pr.review_date,
        pr.performance_score,
        LAG(pr.performance_score) OVER (PARTITION BY e.employee_id ORDER BY pr.review_date) as previous_score,
        pr.goals_met,
        pr.promotion_ready
    FROM employees e
    JOIN departments d ON e.dept_id = d.dept_id
    JOIN performance_reviews pr ON e.employee_id = pr.employee_id
    WHERE e.status = 'Active'
)
SELECT 
    employee_name,
    job_title,
    dept_name,
    performance_score as current_score,
    previous_score,
    CASE 
        WHEN previous_score IS NULL THEN 'First Review'
        WHEN performance_score > previous_score THEN 'Improving'
        WHEN performance_score < previous_score THEN 'Declining'
        ELSE 'Stable'
    END as performance_trend,
    goals_met,
    promotion_ready
FROM performance_trends
WHERE review_date = (SELECT MAX(review_date) FROM performance_reviews WHERE employee_id = performance_trends.employee_id)
ORDER BY performance_score DESC;

-- 4. Training Effectiveness Analysis
SELECT 
    tp.program_name,
    COUNT(et.training_id) as participants,
    AVG(et.score) as avg_score,
    SUM(CASE WHEN et.passed = 1 THEN 1 ELSE 0 END) as passed_count,
    CAST(SUM(CASE WHEN et.passed = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(et.training_id) AS DECIMAL(18,2)) as pass_rate,
    tp.cost_per_employee,
    tp.cost_per_employee * COUNT(et.training_id) as total_investment,
    CAST(tp.cost_per_employee * COUNT(et.training_id) / SUM(CASE WHEN et.passed = 1 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) as cost_per_successful_completion
FROM training_programs tp
JOIN employee_training et ON tp.program_id = et.program_id
GROUP BY tp.program_id, tp.program_name, tp.cost_per_employee
ORDER BY pass_rate DESC;

-- 5. Manager Effectiveness (Span of Control & Team Performance)

SELECT 
    mgr.employee_id as manager_id,
    CONCAT(mgr.first_name, ' ', mgr.last_name) as manager_name,
	mgr.job_title,
    COUNT(emp.employee_id) as team_size,
    CAST(AVG(pr.performance_score) AS DECIMAL(18,2)) as avg_team_performance,
    COUNT(CASE WHEN emp.status = 'Terminated' THEN 1 END) as team_turnover_count,
    CAST(COUNT(CASE WHEN emp.status = 'Terminated' THEN 1 END) * 100.0 / COUNT(emp.employee_id) AS DECIMAL(18,2)) as team_turnover_rate,
    SUM(emp.salary) as total_team_payroll
FROM employees mgr
JOIN employees emp ON mgr.employee_id = emp.manager_id
LEFT JOIN performance_reviews pr ON emp.employee_id = pr.employee_id
GROUP BY mgr.employee_id, mgr.first_name, mgr.last_name, mgr.job_title
HAVING COUNT(emp.employee_id) >= 2  -- Only managers with at least 2 direct reports
ORDER BY avg_team_performance DESC;

-- 6. Tenure Analysis
SELECT 
    b.tenure_bracket,
    COUNT(*) AS employee_count,
    CAST(AVG(e.salary) AS DECIMAL(18,2)) AS avg_salary,
    CAST(AVG(CAST(pr.performance_score AS DECIMAL(5,2))) AS DECIMAL(5,2)) AS avg_performance,
    SUM(CASE WHEN e.status = 'Terminated' THEN 1 ELSE 0 END) AS terminated_count,
    CAST(100.0 * SUM(CASE WHEN e.status = 'Terminated' THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS turnover_rate
FROM employees e
LEFT JOIN performance_reviews pr ON pr.employee_id = e.employee_id
CROSS APPLY (VALUES (
  CASE 
    WHEN DATEDIFF(DAY, e.hire_date, COALESCE(e.termination_date, GETDATE())) < 365  THEN '< 1 year'
    WHEN DATEDIFF(DAY, e.hire_date, COALESCE(e.termination_date, GETDATE())) < 730  THEN '1-2 years'
    WHEN DATEDIFF(DAY, e.hire_date, COALESCE(e.termination_date, GETDATE())) < 1825 THEN '2-5 years'
    WHEN DATEDIFF(DAY, e.hire_date, COALESCE(e.termination_date, GETDATE())) < 3650 THEN '5-10 years'
    ELSE '10+ years'
  END
)) b(tenure_bracket)
GROUP BY b.tenure_bracket
ORDER BY CASE b.tenure_bracket
  WHEN '< 1 year' THEN 1
  WHEN '1-2 years' THEN 2
  WHEN '2-5 years' THEN 3
  WHEN '5-10 years' THEN 4
  ELSE 5
END;

-- 7. Hiring Trends Analysis
-- By Year 
SELECT 
    YEAR(hire_date) as hire_year,
    COUNT(employee_id) as new_hires,
    CAST(AVG(salary) AS DECIMAL(18,2)) as avg_starting_salary
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
GROUP BY YEAR(hire_date)
ORDER BY hire_year DESC;

-- By Year and Dept 
SELECT 
    YEAR(hire_date) as hire_year,
    COUNT(employee_id) as new_hires,
    d.dept_name,
    CAST(AVG(salary) AS DECIMAL(18,2)) as avg_starting_salary
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
GROUP BY YEAR(hire_date), d.dept_name
ORDER BY hire_year DESC;

-- By Month and Dept
SELECT 
    YEAR(hire_date) as hire_year,
    MONTH(hire_date) as hire_month,
    COUNT(employee_id) as new_hires,
    d.dept_name,
    CAST(AVG(salary) AS DECIMAL(18,2)) as avg_starting_salary
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
GROUP BY YEAR(hire_date), MONTH(hire_date), d.dept_name
ORDER BY hire_year DESC, hire_month DESC;

-- 8. High Performer Identification
SELECT 
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) as employee_name,
    e.job_title,
    d.dept_name,
    e.hire_date,
    DATEDIFF(DAY, e.hire_date, GETDATE()) AS days_tenure,
    pr.performance_score,
    pr.promotion_ready,
    et.training_programs_completed,
    CASE 
        WHEN pr.performance_score >= 4.5 THEN 'Star Performer'
        WHEN pr.performance_score >= 4.0 AND pr.performance_score < 4.5 THEN 'High Performer'
        WHEN pr.performance_score >= 3.5 THEN 'Performer'
        ELSE 'Needs Training'
    END as performance_category
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
JOIN (
    SELECT employee_id, performance_score, promotion_ready
    FROM performance_reviews pr1
    WHERE review_date = (SELECT MAX(review_date) FROM performance_reviews pr2 WHERE pr2.employee_id = pr1.employee_id)
) pr ON e.employee_id = pr.employee_id
LEFT JOIN (
    SELECT employee_id, COUNT(*) as training_programs_completed
    FROM employee_training
    WHERE passed = 1
    GROUP BY employee_id
) et ON e.employee_id = et.employee_id
WHERE e.status = 'Active'

ORDER BY pr.performance_score DESC;
