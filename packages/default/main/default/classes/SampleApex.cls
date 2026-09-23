public with sharing class SampleApex {
    public String sampleString { get; set; }

    public SampleApex() {
        this.sampleString = '';
    }

    public void setSampleString(String s) {
        this.sampleString = s;
    }

    public String getSampleString() {
        return this.sampleString;
    }

    public String helloWorld() {
        return 'Hello, world! : ' + sampleString;
    }
}