from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(1, 5)

    @task
    def view_main_page(self):
        self.client.get("/docs")

    @task(3)
    def create_user(self):
        self.client.post("/users/", json={"name": "Test User", "login": "testlogin", "password": "testpassword"})