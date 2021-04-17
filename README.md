#Description
Smart contract performs the following features:
* User pushes collateral to smart contract, and will pay fees (calculated by each type of token)
* The lender makes an offer
* The borrower will choose one of the created offers, after choosing it will create the corresponding contract between the offer and the collateral.
* Admin will create the payment term (the parameter is calculated at the beginning of the period), the borrower will pay based on these corresponding parameters.
* When the borrower pays off the loan + interest, the collateral will be returned to the borrower.
* When the borrower does not pay off the term, the collateral will be sent to the lender.
