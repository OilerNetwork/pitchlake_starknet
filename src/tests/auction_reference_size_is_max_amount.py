print ("########################################################################################")
print ("SIZE IS THE MAXIMUM AMOUNT THE BIDDERS ARE WILLING TO PAY FOR THAT BID")

# Define the bids
bids = [
    {"id": 1, "size": 2, "price": 20},
    {"id": 2, "size": 4, "price": 11},
    {"id": 3, "size": 5, "price": 11},
    {"id": 4, "size": 3, "price": 2},
    {"id": 5, "size": 7, "price": 0.5},
    {"id": 6, "size": 5, "price": 0.3},
]

# bids = [
#     {"id": 1, "size": 2, "price": 20},
#     {"id": 2, "size": 4, "price": 11},
#     {"id": 3, "size": 5, "price": 11},
#     {"id": 4, "size": 3, "price": 2},
#     {"id": 5, "size": 7, "price": 0.5},
#     {"id": 6, "size": 5, "price": 0.3},
# ]


reserve_price = .1
filtered_bids = [bid for bid in bids if bid['price'] >= reserve_price]
removed_bids = [bid for bid in bids if bid['price'] < reserve_price]

# Print the removed bids
for bid in removed_bids:
    print(f"Bid with ID {bid['id']} was removed due to a price below the reserve price.")

# Sort bids by price from highest to lowest
bids = sorted(bids, key=lambda x: (-x['price'], x['size'], x['id']))

options_available = 10000000  # total number of options
clearing_price = 0

for current_price in [bid['price'] for bid in filtered_bids]:
    # following line calculates the total units of the item that would be bought at the current_price.
    total_units = sum([min(bid['size'] / current_price, options_available) for bid in filtered_bids if bid['price'] >= current_price])
    if total_units >= options_available:
        clearing_price = current_price
        break

if not clearing_price:
    clearing_price = filtered_bids[-1]['price']

print(f"Clearing price of the auction is {clearing_price:.2f}")

if clearing_price:
    print(f"Clearing price of the auction is {clearing_price:.2f}")
    # Distribute options based on clearing price
    options_left = options_available
    refunded_bidders = []

    for bid in filtered_bids:
        if bid['price'] < clearing_price:
            print(f"Bidder {bid['id']} doesn't get any tokens (and full bidding token refund)")
        else:
            tokens_to_give = min(options_left, bid['size'] / clearing_price)
            options_left -= tokens_to_give

            refund_amount = bid['size'] - tokens_to_give * clearing_price

            if tokens_to_give > 0:
                print(f"Bidder {bid['id']} gets {tokens_to_give:.2f} tokens")
                if refund_amount > 0:
                    refunded_bidders.append((bid['id'], refund_amount))
            else:
                print(f"Bidder {bid['id']} doesn't get any tokens")
    
    for bidder_id, refund_amount in refunded_bidders:
        print(f"Bidder {bidder_id} gets a refund of {refund_amount:.2f}")
        
    if options_left > 0:
        print(f"{options_left:.2f} options remain undistributed.")

else:
    print("All tokens could not be distributed using these bids.")