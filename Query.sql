--1.) List all dishes with a price lower than 15 euros
SELECT d.Name AS DishName, rd.Price
FROM RestaurantDish rd
JOIN Dishes d ON rd.DishID = d.DishID
WHERE rd.Price < 15;

--2.) List all orders from 2023. with a total value greater than 50 euros
SELECT OrderID, OrderDate, TotalAmount
FROM Orders
WHERE EXTRACT(YEAR FROM OrderDate) = 2023 AND TotalAmount > 50;

--3.) List all delivery drivers with more than 100 successfully completed deliveries to date
SELECT s.StaffID, s.Name, s.Surname, COUNT(d.DeliveryID) AS CompletedDeliveries
FROM Staff s
JOIN Deliveries d ON s.StaffID = d.StaffID
GROUP BY s.StaffID, s.Name, s.Surname
HAVING COUNT(d.DeliveryID) > 100;

--4.) List all chefs working in restaurants in Zagreb
SELECT s.Name AS ChefName, s.Surname AS ChefSurname, r.Name AS RestaurantName
FROM Staff s
JOIN Restaurants r ON s.RestaurantID = r.RestaurantID
JOIN Cities c ON r.CityID = c.CityID
WHERE s.Role = 'Chef' AND c.Name = 'Zagreb';

--5.) List the number of orders for each restaurant in Split during 2023.
SELECT r.Name AS RestaurantName, COUNT(o.OrderID) AS OrderCount
FROM Orders o
JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
JOIN Cities c ON r.CityID = c.CityID
WHERE c.Name = 'Split'
  AND EXTRACT(YEAR FROM o.OrderDate) = 2023
GROUP BY r.Name;

--6.) List all dishes in the "Desserts" category ordered more than 10 times in December 2023.
SELECT d.Name AS DishName, COUNT(od.OrderDetailID) AS OrderCount
FROM Dishes d
JOIN DishCategories dc ON d.CategoryID = dc.CategoryID
JOIN RestaurantDish rd ON d.DishID = rd.DishID
JOIN OrderDetails od ON rd.RestaurantID = od.RestaurantID AND rd.DishID = od.DishID
JOIN Orders o ON od.OrderID = o.OrderID
WHERE dc.Name = 'Dessert'
  AND EXTRACT(MONTH FROM o.OrderDate) = 12
  AND EXTRACT(YEAR FROM o.OrderDate) = 2023
GROUP BY d.Name
HAVING COUNT(od.OrderDetailID) > 10;

--7.) List the number of orders for users with a last name starting with "M"
SELECT u.Name,u.Surname, COUNT(o.OrderID) AS OrderCount
FROM Users u
JOIN Orders o ON u.UserID = o.UserID
WHERE UPPER(u.Surname) LIKE 'M%'
GROUP BY u.Name,u.Surname;

--8.) List the average rating for restaurants in Rijeka
SELECT r.Name AS RestaurantName, 
       ROUND(AVG(COALESCE(rw.OrderRating, 0) + COALESCE(rw.DeliveryRating, 0)) / 2,2) AS AverageRating
FROM Restaurants r
JOIN Cities c ON r.CityID = c.CityID
JOIN Orders o ON r.RestaurantID = o.RestaurantID
LEFT JOIN Reviews rw ON o.OrderID = rw.OrderID
WHERE c.Name = 'Rijeka'
GROUP BY r.Name;

--9.) List all restaurants with a capacity greater than 30 tables and offer delivery
SELECT r.Name AS RestaurantName, r.Capacity
FROM Restaurants r
JOIN Orders o ON r.RestaurantID = o.RestaurantID
WHERE r.Capacity > 30
  AND o.OrderType = 'Delivery'
GROUP BY r.Name, r.Capacity;

--10.) Remove dishes from the menu that have not been ordered in the last 2 years
DELETE FROM RestaurantDish
WHERE DishID IN (
    SELECT rd.DishID
    FROM RestaurantDish rd
    LEFT JOIN OrderDetails od ON rd.RestaurantID = od.RestaurantID AND rd.DishID = od.DishID
    LEFT JOIN Orders o ON od.OrderID = o.OrderID
    WHERE (o.OrderDate < NOW() - INTERVAL '2 years' OR o.OrderDate IS NULL)
    GROUP BY rd.DishID
    HAVING COUNT(o.OrderID) = 0
);

--11.) Delete loyalty cards of users who have not ordered any dish in the last year
DELETE FROM LoyaltyCards
WHERE UserID IN (
    SELECT u.UserID
    FROM Users u
    WHERE NOT EXISTS (
        SELECT 1
        FROM Orders o
        WHERE o.UserID = u.UserID
          AND o.OrderDate >= NOW() - INTERVAL '1 year'
    )
);













