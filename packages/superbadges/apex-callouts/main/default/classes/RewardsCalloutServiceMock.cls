@isTest
global class RewardsCalloutServiceMock implements HttpCalloutMock {
  // Test methods set this before invoking the callout to simulate a specific response scenario.
  global static Integer statusCode = 200;

  global HttpResponse respond(HttpRequest request) {
    HttpResponse response = new HttpResponse();
    response.setHeader('Content-Type', 'application/json');

    if (statusCode == 400) {
      response.setStatusCode(400);
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'code' => 400,
            'description' => 'Bad Request'
          }
        )
      );
      return response;
    }

    if (statusCode == 500) {
      response.setStatusCode(500);
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'code' => 500,
            'description' => 'Internal Server Error'
          }
        )
      );
      return response;
    }

    String endpoint = request.getEndpoint();

    if (endpoint.endsWith('/rewards')) {
      response.setStatusCode(201);
      response.setBody(
        JSON.serialize(new Map<String, Object>{ 'message' => 'Success' })
      );
    } else if (endpoint.endsWith('/journey/completion')) {
      response.setStatusCode(200);
      response.setBody(
        JSON.serialize(new Map<String, Object>{ 'points' => 500 })
      );
    } else if (endpoint.endsWith('/engagement-rate')) {
      response.setStatusCode(200);
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'status' => 'Great',
            'recommendation' => 'Using reminders can help to improve it further.'
          }
        )
      );
    } else if (endpoint.contains('/journeys/')) {
      response.setStatusCode(200);
      response.setBody(
        JSON.serialize(
          new List<Map<String, Object>>{
            new Map<String, Object>{
              'name' => 'Appy\'s Aerobic Adventure',
              'type' => 'Physical',
              'description' => 'An aerobic exercise challenge involving dance, Zumba, or aerobics routines.',
              'accessible' => false,
              'points' => 1500,
              'metric-type' => 'Minutes',
              'goal' => 30
            }
          }
        )
      );
    } else {
      response.setStatusCode(404);
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{ 'code' => 404, 'description' => 'Not Found' }
        )
      );
    }

    return response;
  }
}
