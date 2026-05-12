trigger LeadTrigger on Lead (after insert) {
    LeadTriggerHandler.afterInsert(Trigger.new);
}