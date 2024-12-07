INSERT INTO Deliveries (OrderID, StaffID, DeliveryTime)
SELECT o.OrderID, s.StaffID, CURRENT_TIMESTAMP
FROM Orders o
JOIN Staff s ON o.RestaurantID = s.RestaurantID
WHERE s.Role = 'Delivery Person'
AND o.OrderID NOT IN (
    SELECT DISTINCT d.OrderID
    FROM Deliveries d
)