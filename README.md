# Attendance System v2 (Vercel + Supabase, free)

## Supabase
1. Pehle wala schema chalaya tha to pehle ye chalao:
   `drop table if exists attendance, salaries, employees cascade;`
2. `schema.sql` poora SQL Editor me Run karo.
3. Authentication > Users > Add user (admin email+password, auto confirm). Sign-ups OFF kar do.
4. `insert into admins select id from auth.users where email = 'tumhara@email.com';`
5. Project Settings > API se URL aur anon key `index.html` ke top me daalo.

## Vercel
GitHub pe push karo > Vercel me import > Framework "Other" > Deploy.

## Use
- Staff tab: employee add karo, naam + salary + 4-6 number ka PIN.
- Employees website kholkar "Attendance lagao" me naam + PIN daalke khud IN / Lunch / OUT karte hain (time server se aata hai).
- Baaki sab (attendance, report, salary) sirf admin login ke baad dikhta hai.
