from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from boto3.dynamodb.conditions import Key
from pydantic import BaseModel, Field
from datetime import datetime
from uuid import uuid4
import logging
import boto3

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Sistema de Usuários e Posts")

# Configurando o cliente do DynamoDB
dynamodb = boto3.resource('dynamodb')
usersTable = dynamodb.Table('UsersTable')
postsTable = dynamodb.Table('PostsTable')

class UserInput(BaseModel):
    name: str = Field(..., example="João Batista", description="Nome do usuário")
    login: str = Field(..., example="joaob", description="Login do usuário")
    password: str = Field(..., example="123456", description="Senha do usuário")

class UserResponse(UserInput):
    id: str  # Alterado para string para acomodar o UUID

class PostInput(BaseModel):
    content: str = Field(..., example="Olá, mundo!", description="Conteúdo do post")
    user_id: str = Field(..., example="3dcc40bd-cd17-45ea-8a9f-eff3cf36603f", description="ID do usuário referenciado")

class PostUpdateInput(BaseModel):
    content: str = Field(..., example="Updated content", description="Updated content of the post")

class PostResponse(PostInput):
    id: str  # ID as a string to accommodate the UUID
    date: str  # ISO 8601 formatted date string
    last_update: str  # ISO 8601 formatted date string

@app.get("/")
def health_check():
    return {"status": "ok"}, 200

@app.post("/users/", response_model=UserResponse)
def create_user(user: UserInput):
    logger.info(f"Attempting to create user with login: {user.login}")
    try:
        user_id = str(uuid4())
        new_user = user.dict()
        new_user['id'] = user_id
        usersTable.put_item(Item=new_user)
        logger.info("User created successfully with ID: {user_id}")
        return new_user
    except Exception as e:
        logger.error("Failed to create user", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/users/{user_id}")
def read_user(user_id: str):
    logger.info(f"Fetching user with ID: {user_id}")
    try:
        response = usersTable.get_item(Key={'id': user_id})
        user = response.get('Item')
        if not user:
            logger.warning("User not found")
            raise HTTPException(status_code=404, detail="Usuário não encontrado")
        return user
    except Exception as e:
        logger.error("Failed to fetch user", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/users/{user_id}", response_model=UserResponse)
def update_user(user_id: str, user: UserInput):
    logger.info(f"Updating user with ID: {user_id}")
    try:
        usersTable.update_item(
            Key={'id': user_id},
            UpdateExpression='SET #name = :name, #login = :login, #password = :password',
            ExpressionAttributeValues={
                ':name': user.name,
                ':login': user.login,
                ':password': user.password
            },
            ExpressionAttributeNames={
                '#name': 'name',
                '#login': 'login',
                '#password': 'password'
            }
        )
        updated_user = usersTable.get_item(Key={'id': user_id})['Item']
        logger.info("User updated successfully")
        return updated_user
    except Exception as e:
        logger.error("Failed to update user", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/users/{user_id}")
def delete_user(user_id: str):
    logger.info(f"Deleting user with ID: {user_id}")
    try:
        # First, retrieve all posts for the user
        response = postsTable.scan(
            FilterExpression=Key('user_id').eq(user_id)
        )
        posts = response.get('Items', [])

        # Delete all posts by this user
        for post in posts:
            postsTable.delete_item(Key={'id': post['id']})

        # After all posts are deleted, delete the user
        usersTable.delete_item(Key={'id': user_id})
        return {"message": "Usuário e todos os posts relacionados foram deletados com sucesso"}
    except Exception as e:
        logger.error("Failed to delete user", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/posts/", response_model=PostResponse)
def create_post(post: PostInput):
    logger.info(f"Creating post for user ID: {post.user_id}")
    try:
        post_id = str(uuid4())
        now = datetime.utcnow().isoformat()
        new_post = post.dict()
        new_post.update({
            'id': post_id,
            'date': now,
            'last_update': now
        })
        postsTable.put_item(Item=new_post)
        return new_post
    except Exception as e:
        logger.error("Failed to create post", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/posts/{post_id}")
def read_post(post_id: str):
    logger.info(f"Fetching post with ID: {post_id}")
    try:
        response = postsTable.get_item(Key={'id': post_id})
        post = response.get('Item')
        if not post:
            logger.warning("Post not found")
            raise HTTPException(status_code=404, detail="Post não encontrado")
        return post
    except Exception as e:
        logger.error("Failed to fetch post", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/posts/{post_id}", response_model=PostResponse)
def update_post(post_id: str, post: PostUpdateInput):
    logger.info(f"Updating post with ID: {post_id}")
    try:
        now = datetime.utcnow().isoformat()
        # Fetch the current post to retain the user_id
        existing_post = postsTable.get_item(Key={'id': post_id})
        existing_user_id = existing_post.get('Item', {}).get('user_id')

        if not existing_post.get('Item'):
            raise HTTPException(status_code=404, detail="Post not found")

        # Update only the content and last_update fields
        postsTable.update_item(
            Key={'id': post_id},
            UpdateExpression='SET #content = :content, #last_update = :last_update',
            ExpressionAttributeValues={
                ':content': post.content,
                ':last_update': now
            },
            ExpressionAttributeNames={
                '#content': 'content',
                '#last_update': 'last_update'
            }
        )

        # Retrieve updated post to return
        updated_post = postsTable.get_item(Key={'id': post_id})['Item']
        # Ensure user_id is still the same and attach dates from the database
        updated_post['user_id'] = existing_user_id
        updated_post['date'] = existing_post.get('Item', {}).get('date', now)
        updated_post['last_update'] = now
        return updated_post
    except Exception as e:
        logger.error("Failed to update post", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/posts/{post_id}")
def delete_post(post_id: str):
    logger.info(f"Deleting post with ID: {post_id}")
    try:
        postsTable.delete_item(Key={'id': post_id})
        logger.info("Post deleted successfully")
        return {"message": "Post deletado com sucesso"}
    except Exception as e:
        logger.error("Failed to delete post", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/users/{user_id}/posts")
def list_user_posts(user_id: str):
    logger.info(f"Listing posts for user ID: {user_id}")
    try:
        response = postsTable.scan(FilterExpression=boto3.dynamodb.conditions.Attr('user_id').eq(user_id))
        posts = response.get('Items', [])
        logger.info(f"Found {len(posts)} posts for user")
        return posts
    except Exception as e:
        logger.error("Failed to list posts", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))