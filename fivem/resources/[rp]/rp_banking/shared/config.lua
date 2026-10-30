RpBanking = RpBanking or {}

RpBanking.Config = {
  -- Server-side distance check in metres; the client uses the same value.
  radius = 3.0,
  maxAmount = 10000000,
  -- Per character: at most rateMax requests per rateWindowS seconds.
  rateMax = 5,
  rateWindowS = 10,
  -- Bank counters (plain tables so the logic can be unit tested). Approximate
  -- coordinates of the stock GTA V branches; verify in game before release.
  locations = {
    { label = 'Fleeca Legion Square', x = 149.46, y = -1042.09, z = 29.37 },
    { label = 'Fleeca Hawick', x = 314.23, y = -278.83, z = 54.17 },
    { label = 'Fleeca Burton', x = -350.80, y = -49.57, z = 49.04 },
    { label = 'Fleeca Rockford', x = -1213.00, y = -330.39, z = 37.79 },
    { label = 'Fleeca Great Ocean', x = -2962.71, y = 482.92, z = 15.70 },
    { label = 'Fleeca Route 68', x = 1175.07, y = 2706.64, z = 38.09 },
    { label = 'Blaine County Savings', x = -112.20, y = 6469.29, z = 31.63 },
    { label = 'Pacific Standard', x = 246.64, y = 223.20, z = 106.29 },
  },
}
