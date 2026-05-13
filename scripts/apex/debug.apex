List<Contact> contacts = [SELECT Id, AccountId FROM Contact WHERE Email = 'shinme.rai@widsley.com'];
System.debug('Contact AccountId: ' + contacts[0].AccountId);

List<Opportunity> opps = [SELECT Id, StageName, AccountId FROM Opportunity WHERE AccountId = :contacts[0].AccountId];
System.debug('Total Opp count: ' + opps.size());
for(Opportunity o : opps) {
    System.debug('StageName: ' + o.StageName);
}