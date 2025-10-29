public class OpportunityTriggerHandler {
    
    public void run() {
        
        if (Trigger.isBefore) {
            if (Trigger.isInsert) {
                beforeInsert();
            }
            else if (Trigger.isUpdate) {
                beforeUpdate();
            }
            else if (Trigger.isDelete) {
                beforeDelete();
            }
        }
        
        if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                afterInsert();
            }
            else if (Trigger.isUpdate) {
                afterUpdate();
            }
            else if (Trigger.isDelete) {
                afterDelete();
            }
            else if (Trigger.isUndelete) {
                afterUndelete();
            }
        }
    }
    
    private void beforeInsert() {
        OpportunityHelper.setType(Trigger.new);
    }
    
    private void beforeUpdate() {
        OpportunityHelper.updateDescriptionFromStage(Trigger.new);
        OpportunityHelper.validateAmount(Trigger.new);
        OpportunityHelper.setPrimaryContactCEO(Trigger.new);
    }
    
    private void beforeDelete() {
        OpportunityHelper.validateCloseOpportunity(Trigger.old);
        OpportunityHelper.deleteCloseWonOpps(Trigger.old);
    }
    
    private void afterInsert() {
        OpportunityHelper.insertTask(Trigger.new);
    }
    
    private void afterUpdate() {
        // No logic currently needed
    }
    
    private void afterDelete() {
        OpportunityHelper.notifyOwnersOpportunityDeleted(Trigger.old);
    }
    
    private void afterUndelete() {
        //cast the map properly Map<Id, SObject> as Map<Id, Opportunity>
        List<Opportunity> opps = (List<Opportunity>) Trigger.new;
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>(opps);
        OpportunityHelper.assignPrimaryContact(oppMap);
    }
}