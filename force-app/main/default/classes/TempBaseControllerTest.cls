@isTest
public class TempBaseControllerTest {
    
    @isTest static void testInitDo(){
		List<Template__c> tempList = new List<Template__c>();
        Template__c temp = new Template__c(Name='testTemplate');
        tempList.add(temp);
        insert tempList;
        Id recordId = tempList[0].Id;
        TempBaseController.initDo(recordId);
    }
    
    //(Id recordId)
    @isTest static void testGetTaskList(){
        
        List<Template__c> tempList = new List<Template__c>();
        Template__c temp = new Template__c(Name='testTemplate');
        tempList.add(temp);
        insert tempList;
        
        Id recordIdMain = TempBaseController.getRecIdinTM('Main');
        Id recordIdSub = TempBaseController.getRecIdinTM('Sub');
        
        //make data
        List<TaskMaster__c> mainTaskList = new List<TaskMaster__c>();
        for(Integer i=0;i<5;i++){
            TaskMaster__c tmMain = new TaskMaster__c(Name='test'+i,
                                                     Template__c = tempList[0].Id,
                                                     RecordTypeId=recordIdMain);
            mainTaskList.add(tmMain);
            insert tmMain;
            
            for(Integer k=0;k<5;k++){
                TaskMaster__c tmSub = new TaskMaster__c(Name='test'+k,
                                                        RecordTypeId=recordIdSub,
                                                        TaskMaster__c=tmMain.Id);
                mainTaskList.add(tmSub);
                insert tmSub;
            }
        }
        
        Test.startTest();
        List<TaskMaster__c> taskList = TempBaseController.getTaskList(tempList[0].Id);
        Test.stopTest();
    }
    
    @isTest static void testSetTasks(){
        //setTasks(List<TaskMaster__c> taskList, Id recordId, List<Id> delList)
        
        List<TaskMaster__c> taskList = new List<TaskMaster__c>();        
        
        List<Template__c> tempList = new List<Template__c>();
        Template__c temp = new Template__c(Name='testTemplate');
        tempList.add(temp);
        insert tempList;
        Id recordId = tempList[0].Id;
        
        List<Id> delList = new List<Id>();
        
        //make data
        Id recordIdMain = TempBaseController.getRecIdinTM('Main');
        Id recordIdSub = TempBaseController.getRecIdinTM('Sub');
        
        for(Integer i=0;i<5;i++){
            TaskMaster__c tmMain = new TaskMaster__c(Name='test'+i,
                                                     Template__c = tempList[0].Id,
                                                     RecordTypeId=recordIdMain);
            taskList.add(tmMain);
            insert tmMain;
            
            for(Integer k=0;k<5;k++){
                TaskMaster__c tmSub = new TaskMaster__c(Name='test'+k,
                                                        RecordTypeId=recordIdSub,
                                                        TaskMaster__c=tmMain.Id);
                taskList.add(tmSub);
                insert tmSub;
            }
        }
        
        Test.startTest();
        TempBaseController.setTasks(taskList,recordId,delList);
        Test.stopTest();
    }

    
    
}